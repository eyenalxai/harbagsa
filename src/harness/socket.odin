#+vet explicit-allocators
package harness

import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:strings"
import "core:sys/posix"

SOCKET_RECV_BUFFER :: 8192

Socket_Ready :: struct {
	ok:     bool   `json:"ok"`,
	ready:  bool   `json:"ready"`,
	socket: string `json:"socket"`,
}

serve_socket :: proc(runtime: ^Session_Runtime, path: string) -> int {
	server, server_error := socket_server(path)
	if server_error != "" {
		print_summary_failure(server_error, EXIT_RENDER)
		return EXIT_RENDER
	}
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	defer {
		posix.close(server)
		posix.unlink(cpath)
	}
	socket_ready(path)

	for !runtime.session.quit {
		client := posix.accept(server, nil, nil)
		if client < 0 {
			log.error("harness: socket accept failed")
			break
		}
		serve_client(runtime, client)
		posix.close(client)
	}
	if runtime.had_error || len(runtime.session.failures) > 0 {
		return EXIT_CHECK
	}
	return runtime.exit_code
}

@(private)
socket_server :: proc(path: string) -> (fd: posix.FD, error: string) {
	if len(path) == 0 {
		return -1, "socket path is empty"
	}
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	posix.unlink(cpath)
	fd = posix.socket(.UNIX, .STREAM)
	if fd < 0 {
		return -1, "cannot create the Unix socket"
	}

	address: posix.sockaddr_un
	address.sun_family = .UNIX
	if len(path) >= len(address.sun_path) {
		posix.close(fd)
		return -1, "socket path is too long"
	}
	for index in 0 ..< len(path) {
		address.sun_path[index] = c.char(path[index])
	}
	address.sun_path[len(path)] = 0
	if posix.bind(fd, cast(^posix.sockaddr)&address, posix.socklen_t(size_of(address))) != .OK {
		posix.close(fd)
		return -1, "cannot bind the Unix socket"
	}
	if posix.listen(fd, 4) != .OK {
		posix.close(fd)
		return -1, "cannot listen on the Unix socket"
	}
	return fd, ""
}

@(private)
socket_ready :: proc(path: string) {
	data, marshal_error := json.marshal(
		Socket_Ready{ok = true, ready = true, socket = path},
		{},
		context.allocator,
	)
	if marshal_error != nil {
		return
	}
	defer delete(data, context.allocator)
	fmt.println(string(data))
}

@(private)
serve_client :: proc(runtime: ^Session_Runtime, client: posix.FD) {
	pending := make([dynamic]u8, 0, 4096, context.allocator)
	defer delete(pending)
	chunk: [SOCKET_RECV_BUFFER]u8
	for !runtime.session.quit {
		count := posix.recv(client, raw_data(chunk[:]), len(chunk), {})
		if count <= 0 {
			break
		}
		append(&pending, ..chunk[:int(count)])
		for {
			newline := -1
			for character, index in pending[:] {
				if character == '\n' {
					newline = index
					break
				}
			}
			if newline < 0 {
				if len(pending) > MAX_SESSION_LINE {
					clear(&pending)
				}
				break
			}
			line := string(pending[:newline])
			if !send_reply(client, runtime_handle_line(runtime, line)) {
				return
			}
			copy(pending[:], pending[newline + 1:])
			resize(&pending, len(pending) - (newline + 1))
		}
	}
}

@(private)
send_reply :: proc(client: posix.FD, data: []byte) -> bool {
	if data == nil {
		return true
	}
	defer delete(data, context.allocator)
	if !send_all(client, data) {
		return false
	}
	return send_all(client, []byte{'\n'})
}

@(private)
send_all :: proc(client: posix.FD, data: []byte) -> bool {
	offset: uint
	for offset < uint(len(data)) {
		sent := posix.send(
			client,
			rawptr(uintptr(raw_data(data)) + uintptr(offset)),
			c.size_t(uint(len(data)) - offset),
			{.NOSIGNAL},
		)
		if sent <= 0 {
			return false
		}
		offset += uint(sent)
	}
	return true
}
