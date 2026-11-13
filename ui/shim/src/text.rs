use rune::{El, Span, text};

pub fn weighted(content: &str, weight: f32, mono: bool) -> El {
    let element = text(content);
    let mut span = Span::new(0, content.len());
    if weight > 0.0 {
        span = span.weight(weight);
    }
    if mono {
        span = span.mono();
    }
    element.spans(vec![span])
}
