// Copyright (C) 2026 Bingshan Chang <chang@bingshan.org>

// emacs-jieba-rs is free software: you can redistribute it and/or modify it under the terms of the
// GNU General Public License as published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.

// emacs-jieba-rs is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See
// the GNU General Public License for more details.

// You should have received a copy of the GNU General Public License along with emacs-jieba-rs.  If
// not, see <https://www.gnu.org/licenses/>.

use std::sync::LazyLock;

use emacs::{Env, Result, Vector, defun};
use jieba_rs::Jieba;

emacs::plugin_is_GPL_compatible!();

static JIEBA: LazyLock<Jieba> = LazyLock::new(Jieba::new);

#[defun]
fn segment(env: &Env, text: String) -> Result<Vector<'_>> {
    let words = JIEBA.cut(&text, false);
    let len = words.len();
    let vec = env.make_vector(len, ())?;
    for (i, token) in words.iter().enumerate() {
        vec.set(i, token.word)?;
    }
    Ok(vec)
}

#[emacs::module(name = "jieba-rs")]
fn init(_: &Env) -> Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_segment_precise() {
        let words: Vec<&str> = JIEBA
            .cut("我们中出了一个叛徒", false)
            .iter()
            .map(|t| t.word.as_ref())
            .collect();
        assert_eq!(words, vec!["我们", "中", "出", "了", "一个", "叛徒"]);
    }

    #[test]
    fn test_segment_empty() {
        assert!(JIEBA.cut("", false).is_empty());
    }
}
