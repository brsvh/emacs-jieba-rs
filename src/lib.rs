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

use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};

use emacs::{Env, FromLisp, IntoLisp, Result, Value, Vector, defun};
use jieba_rs::{Jieba, KeywordExtract, TextRank, TfIdf};

emacs::plugin_is_GPL_compatible!();

/// A checked Lisp string that preserves embedded and trailing NULs.
struct LispString(String);

impl FromLisp<'_> for LispString {
    fn from_lisp(value: Value<'_>) -> Result<Self> {
        let env = value.env;
        let size: usize =
            env.call("string-bytes", (value,))?.into_rust()?;
        // Emacs byte counts fit in isize, leaving room for a terminator.
        let mut bytes = vec![0; size + 1];
        let len = value.copy_string_contents(&mut bytes)?.len();
        bytes.truncate(len);
        match String::from_utf8(bytes) {
            Ok(text) => Ok(Self(text)),
            Err(_) => env.signal(
                "wrong-type-argument",
                (env.intern("unicode-string-p")?, value),
            ),
        }
    }
}

#[derive(Default)]
struct Dictionary {
    jieba: Jieba,
    // Upstream updates frequencies, but retains tags for existing words.
    tags: HashMap<String, String>,
    version: u64,
}

static JIEBA: LazyLock<Mutex<Dictionary>> =
    LazyLock::new(|| Mutex::new(Dictionary::default()));

static TF_IDF: LazyLock<TfIdf> = LazyLock::new(TfIdf::default);
static TEXT_RANK: LazyLock<TextRank> =
    LazyLock::new(TextRank::default);

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
    text: LispString,
    hmm: Value<'a>,
) -> Result<Vector<'a>> {
    let text = text.0;
    let words =
        JIEBA.lock().unwrap().jieba.cut(&text, hmm.is_not_nil());
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
fn segment_all(env: &Env, text: LispString) -> Result<Vector<'_>> {
    let text = text.0;
    let words = JIEBA.lock().unwrap().jieba.cut_all(&text);
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
    text: LispString,
    hmm: Value<'a>,
) -> Result<Vector<'a>> {
    let text = text.0;
    let words = JIEBA
        .lock()
        .unwrap()
        .jieba
        .cut_for_search(&text, hmm.is_not_nil());
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
    text: LispString,
    hmm: Value<'a>,
) -> Result<Vector<'a>> {
    let text = text.0;
    let dictionary = JIEBA.lock().unwrap();
    let jieba = &dictionary.jieba;
    let tags = jieba.tag(&text, hmm.is_not_nil());
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
            dictionary
                .tags
                .get(tag.word)
                .map(String::as_str)
                .unwrap_or(tag.tag)
                .into_lisp(env)?,
        ])?;
        vec.set(i, plist)?;
    }
    Ok(vec)
}

/// Load a user dictionary from PATH.
#[defun]
fn load_user_dict(env: &Env, path: LispString) -> Result<()> {
    let path = path.0;
    let contents = match std::fs::read_to_string(&path) {
        Ok(f) => f,
        Err(e) => {
            return env.signal("file-error", (e.to_string(), path));
        }
    };
    let mut dictionary = JIEBA.lock().unwrap();
    dictionary.version = dictionary.version.wrapping_add(1);
    match dictionary.jieba.load_dict(&mut contents.as_bytes()) {
        Ok(()) => {
            for line in contents.lines() {
                let mut fields = line.split_whitespace();
                if let (Some(word), Some(_freq), Some(tag)) =
                    (fields.next(), fields.next(), fields.next())
                {
                    dictionary.tags.insert(word.into(), tag.into());
                }
            }
            Ok(())
        }
        Err(e) => env.signal("error", (e.to_string(),)),
    }
}

/// Add WORD to the dictionary.
///
/// When FREQ is nil, a suitable frequency is suggested
/// automatically.  When TAG is nil, no POS tag is assigned.
///
/// Return the assigned frequency.
#[defun]
fn add_word(
    _env: &Env,
    word: LispString,
    freq: Value,
    tag: Value,
) -> Result<usize> {
    let word = word.0;
    let freq_opt: Option<usize> = if freq.is_not_nil() {
        Some(freq.into_rust()?)
    } else {
        None
    };
    let tag_opt: Option<String> = if tag.is_not_nil() {
        Some(tag.into_rust::<LispString>()?.0)
    } else {
        None
    };
    let mut dictionary = JIEBA.lock().unwrap();
    dictionary.version = dictionary.version.wrapping_add(1);
    let freq = dictionary.jieba.add_word(
        &word,
        freq_opt,
        tag_opt.as_deref(),
    );
    if let Some(tag) = tag_opt {
        dictionary.tags.insert(word, tag);
    }
    Ok(freq)
}

/// Return the dictionary version for invalidating segmentation caches.
#[defun]
fn dictionary_version() -> Result<u64> {
    Ok(JIEBA.lock().unwrap().version)
}

/// Extract top-K keywords from TEXT using TF-IDF or TextRank.
///
/// Return a vector of plists with :keyword and :weight.
#[defun]
fn extract_keywords<'a>(
    env: &'a Env,
    text: LispString,
    top_k: Value<'a>,
    method: Value<'a>,
) -> Result<Vector<'a>> {
    let text = text.0;
    let k: usize = if top_k.is_not_nil() {
        top_k.into_rust()?
    } else {
        10
    };
    // At most one keyword can start at each input character.  Bound
    // upstream result allocation even for an arbitrarily large K.
    let k = k.min(text.chars().count());
    let use_tfidf = method.is_not_nil()
        && method.into_rust::<LispString>()?.0 == "tfidf";
    let dictionary = JIEBA.lock().unwrap();
    let jieba = &dictionary.jieba;
    let keywords = if use_tfidf {
        TF_IDF.extract_keywords(jieba, &text, k, vec![])
    } else {
        TEXT_RANK.extract_keywords(jieba, &text, k, vec![])
    };
    let vec = env.make_vector(keywords.len(), ())?;
    for (i, kw) in keywords.iter().enumerate() {
        let plist = env.list(&[
            env.intern(":keyword")?,
            kw.keyword.as_str().into_lisp(env)?,
            env.intern(":weight")?,
            kw.weight.into_lisp(env)?,
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
        let dictionary = JIEBA.lock().unwrap();
        let jieba = &dictionary.jieba;
        let words: Vec<&str> = jieba
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
        let dictionary = JIEBA.lock().unwrap();
        let jieba = &dictionary.jieba;
        assert!(jieba.cut("", false).is_empty());
    }

    #[test]
    fn test_segment_with_hmm() {
        let dictionary = JIEBA.lock().unwrap();
        let jieba = &dictionary.jieba;
        let words: Vec<&str> = jieba
            .cut("我们中出了一个叛徒", true)
            .iter()
            .map(|t| t.word.as_ref())
            .collect();
        assert!(!words.is_empty());
    }

    #[test]
    fn test_segment_all() {
        let dictionary = JIEBA.lock().unwrap();
        let jieba = &dictionary.jieba;
        let words: Vec<&str> = jieba
            .cut_all("南京市长江大桥")
            .iter()
            .map(|t| t.word.as_ref())
            .collect();
        assert!(words.contains(&"南京"));
    }

    #[test]
    fn test_segment_search() {
        let dictionary = JIEBA.lock().unwrap();
        let jieba = &dictionary.jieba;
        let words: Vec<&str> = jieba
            .cut_for_search("南京市长江大桥", true)
            .iter()
            .map(|t| t.word.as_ref())
            .collect();
        assert!(words.contains(&"长江大桥"));
    }

    #[test]
    fn test_segment_tag() {
        let dictionary = JIEBA.lock().unwrap();
        let jieba = &dictionary.jieba;
        let tags = jieba.tag("我是拖拉机学院手扶拖拉机专业的", true);
        assert!(!tags.is_empty());
        assert_eq!(tags[0].word, "我");
        assert_eq!(tags[0].tag, "r");
        assert_eq!(tags[1].word, "是");
        assert_eq!(tags[1].tag, "v");
    }
}
