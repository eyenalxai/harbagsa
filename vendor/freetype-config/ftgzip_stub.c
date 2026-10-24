/* The vendored FreeType is built without zlib, but the sfnt module still
 * references FT_Gzip_Uncompress for WOFF and SVGZ. This build only loads plain
 * TrueType outlines, so the entry point exists to satisfy the linker and fails
 * cleanly (FT_Err_Unimplemented_Feature is 0x07) if a compressed font ever
 * reaches it. */
#include <ft2build.h>
#include FT_GZIP_H

FT_EXPORT( FT_Error )
FT_Gzip_Uncompress( FT_Memory     memory,
                    FT_Byte*      output,
                    FT_ULong*     output_len,
                    const FT_Byte* input,
                    FT_ULong      input_len )
{
  (void)memory;
  (void)output;
  (void)output_len;
  (void)input;
  (void)input_len;

  return (FT_Error)0x07;
}
