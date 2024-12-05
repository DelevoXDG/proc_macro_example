use cairo_lang_macro::{ProcMacroResult, TokenStream, inline_macro};

/// The entry point of procedural macro implementation.
#[inline_macro]
pub fn some(token_stream: TokenStream) -> ProcMacroResult {
    // no-op
    ProcMacroResult::new(token_stream)
}