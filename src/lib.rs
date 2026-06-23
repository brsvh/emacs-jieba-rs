// Copyright (C) 2026 Bingshan Chang <chang@bingshan.org>

// emacs-jieba-rs is free software: you can redistribute it and/or
// modify it under the terms of the GNU General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.

// emacs-jieba-rs is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with emacs-jieba-rs.  If not, see
// <https://www.gnu.org/licenses/>.

use std::sync::LazyLock;

use emacs::{Env, IntoLisp, Result, Value, Vector, defun};
use jieba_rs::Jieba;

emacs::plugin_is_GPL_compatible!();

static JIEBA: LazyLock<Jieba> = LazyLock::new(Jieba::new);

/// Segment TEXT in precise mode.
///
/// Attempt to cut the sentence most accurately.  Suitable for text
/// analysis.
///
/// When HMM is nil, disable new word discovery; when t, enable it.
///
/// Return a vector of word strings.
#[defun]
fn segment<'a>(
    env: &'a Env,
    text: String,
    hmm: Value<'a>,
) -> Result<Vector<'a>> {
    let words = JIEBA.cut(&text, hmm.is_not_nil());
    let len = words.len();
    let vec = env.make_vector(len, ())?;
    for (i, token) in words.iter().enumerate() {
        vec.set(i, token.word)?;
    }
    Ok(vec)
}

/// Segment TEXT in full mode.
///
/// Scan all possible words from the sentence.  Very fast, but cannot
/// resolve ambiguity.
///
/// Return a vector of word strings.
#[defun]
fn segment_all(env: &Env, text: String) -> Result<Vector<'_>> {
    let words = JIEBA.cut_all(&text);
    let len = words.len();
    let vec = env.make_vector(len, ())?;
    for (i, token) in words.iter().enumerate() {
        vec.set(i, token.word)?;
    }
    Ok(vec)
}

/// Segment TEXT in search engine mode.
///
/// Based on precise mode, further cut long words into bigrams and
/// trigrams to improve recall.  Suitable for search engine
/// tokenization.
///
/// When HMM is nil, disable new word discovery; when t, enable it.
///
/// Return a vector of word strings.
#[defun]
fn segment_search<'a>(
    env: &'a Env,
    text: String,
    hmm: Value<'a>,
) -> Result<Vector<'a>> {
    let words = JIEBA.cut_for_search(&text, hmm.is_not_nil());
    let len = words.len();
    let vec = env.make_vector(len, ())?;
    for (i, token) in words.iter().enumerate() {
        vec.set(i, token.word)?;
    }
    Ok(vec)
}

/// Part-of-speech tagging for TEXT.
///
/// When HMM is nil, disable new word discovery; when t, enable it.
///
/// Return a vector of plists, each containing :start, :end, :word,
/// and :category.
#[defun]
fn segment_tag<'a>(
    env: &'a Env,
    text: String,
    hmm: Value<'a>,
) -> Result<Vector<'a>> {
    let tags = JIEBA.tag(&text, hmm.is_not_nil());
    let len = tags.len();
    let vec = env.make_vector(len, ())?;
    for (i, tag) in tags.iter().enumerate() {
        let plist = env.list(&[
            env.intern(":start")?,
            (tag.start as i64).into_lisp(env)?,
            env.intern(":end")?,
            (tag.end as i64).into_lisp(env)?,
            env.intern(":word")?,
            tag.word.into_lisp(env)?,
            env.intern(":category")?,
            tag.tag.into_lisp(env)?,
        ])?;
        vec.set(i, plist)?;
    }
    Ok(vec)
}

#[emacs::module(name = "jieba-rs-module")]
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
        assert_eq!(
            words,
            vec!["我们", "中", "出", "了", "一个", "叛徒"]
        );
    }

    #[test]
    fn test_segment_empty() {
        assert!(JIEBA.cut("", false).is_empty());
    }

    #[test]
    fn test_segment_with_hmm() {
        let words: Vec<&str> = JIEBA
            .cut("我们中出了一个叛徒", true)
            .iter()
            .map(|t| t.word.as_ref())
            .collect();
        assert!(!words.is_empty());
    }

    #[test]
    fn test_segment_all() {
        let words: Vec<&str> = JIEBA
            .cut_all("南京市长江大桥")
            .iter()
            .map(|t| t.word.as_ref())
            .collect();
        assert!(words.contains(&"南京"));
    }

    #[test]
    fn test_segment_search() {
        let words: Vec<&str> = JIEBA
            .cut_for_search("南京市长江大桥", true)
            .iter()
            .map(|t| t.word.as_ref())
            .collect();
        assert!(words.contains(&"长江大桥"));
    }

    #[test]
    fn test_segment_tag() {
        let tags = JIEBA.tag("我是拖拉机学院手扶拖拉机专业的", true);
        assert!(!tags.is_empty());
        assert_eq!(tags[0].word, "我");
        assert_eq!(tags[0].tag, "r");
        assert_eq!(tags[1].word, "是");
        assert_eq!(tags[1].tag, "v");
    }
}
