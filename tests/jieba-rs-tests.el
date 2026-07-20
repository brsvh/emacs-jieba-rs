;;; jieba-rs-tests.el --- Tests for jieba-rs  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Bingshan Chang <chang@bingshan.org>

;; emacs-jieba-rs is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; emacs-jieba-rs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with emacs-jieba-rs.  If not, see
;; <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Integration tests for the jieba-rs Emacs dynamic module.  The
;; module must be loaded before running these tests.

;;; Code:

(require 'ert)
(require 'jieba-rs)
(require 'jieba-rs-module)
(require 'seq)

(ert-deftest jieba-rs-tests-segment-precise ()
  "Basic Chinese word segmentation in precise mode."
  (should (equal (jieba-rs-module-segment "我们中出了一个叛徒" nil)
                 ["我们" "中" "出" "了" "一个" "叛徒"])))

(ert-deftest jieba-rs-tests-segment-empty ()
  "Segmenting an empty string yields an empty vector."
  (should (equal (jieba-rs-module-segment "" nil) [])))

(ert-deftest jieba-rs-tests-segment-single-char ()
  "Segmenting a single Chinese character."
  (should (equal (jieba-rs-module-segment "我" nil) ["我"])))

(ert-deftest jieba-rs-tests-segment-ascii-mixed ()
  "Segmenting text with mixed CJK and ASCII."
  (should (equal (jieba-rs-module-segment "hello世界" nil)
                 ["hello" "世界"])))

(ert-deftest jieba-rs-tests-segment-long-text ()
  "Segmenting longer text yields a non-empty vector."
  (let ((vec (jieba-rs-module-segment "我爱北京天安门天安门上太阳升" nil)))
    (should (vectorp vec))
    (should (> (length vec) 0))))

(ert-deftest jieba-rs-tests-segment-return-type ()
  "Ensure precise segmentation always returns a vector."
  (should (vectorp (jieba-rs-module-segment "测试" nil)))
  (should (vectorp (jieba-rs-module-segment "" nil))))

(ert-deftest jieba-rs-tests-segment-with-hmm ()
  "Segmentation with HMM enabled yields a vector."
  (let ((vec (jieba-rs-module-segment "我们中出了一个叛徒" t)))
    (should (vectorp vec))
    (should (> (length vec) 0))))

(ert-deftest jieba-rs-tests-module-segment-all-works ()
  "Full-mode segmentation returns overlapping sub-words."
  (let ((vec (jieba-rs-module-segment-all "南京市长江大桥")))
    (should (vectorp vec))
    (should (seq-contains-p vec "南京"))))

(ert-deftest jieba-rs-tests-module-segment-all-return-type ()
  "Ensure full-mode segmentation always returns a vector."
  (should (vectorp (jieba-rs-module-segment-all "测试")))
  (should (vectorp (jieba-rs-module-segment-all ""))))

(ert-deftest jieba-rs-tests-module-segment-search-works ()
  "Ensure search segmentation returns bigrams for longer words."
  (let ((vec (jieba-rs-module-segment-search "南京市长江大桥" t)))
    (should (vectorp vec))
    (should (seq-contains-p vec "长江大桥"))))

(ert-deftest jieba-rs-tests-module-segment-search-return-type ()
  "Ensure search segmentation always returns a vector."
  (should (vectorp (jieba-rs-module-segment-search "测试" nil)))
  (should (vectorp (jieba-rs-module-segment-search "" nil))))

(ert-deftest jieba-rs-tests-module-segment-tag-works ()
  "Ensure POS tagging returns a vector of result plists."
  (let ((vec (jieba-rs-module-segment-tag "我是中国人" t)))
    (should (vectorp vec))
    (should (> (length vec) 0))
    (let ((item (aref vec 0)))
      (should (plist-member item :start))
      (should (plist-member item :end))
      (should (plist-member item :word))
      (should (plist-member item :category)))))

(ert-deftest jieba-rs-tests-module-segment-tag-return-type ()
  "Ensure POS tagging always returns a vector."
  (should (vectorp (jieba-rs-module-segment-tag "测试" nil)))
  (should (vectorp (jieba-rs-module-segment-tag "" nil))))

(ert-deftest jieba-rs-tests--format-words ()
  "Join word vectors with vertical-bar separators."
  (should (equal (jieba-rs--format-words ["我" "是" "谁"])
                 "我 | 是 | 谁"))
  (should (equal (jieba-rs--format-words ["hello" "世界"])
                 "hello | 世界"))
  (should (equal (jieba-rs--format-words []) "")))

(ert-deftest jieba-rs-tests--segment-function-arity ()
  "Return the arity of each segment function."
  (should (= (jieba-rs--segment-function-arity
              'jieba-rs-module-segment-all) 1))
  (should (= (jieba-rs--segment-function-arity
              'jieba-rs-module-segment) 2))
  (should (= (jieba-rs--segment-function-arity
              'jieba-rs-module-segment-search) 2)))

(ert-deftest jieba-rs-tests--show-tooltip-noop ()
  "Display text in the echo area when tooltips are disabled."
  (should (stringp (jieba-rs--show-tooltip "test"))))

(ert-deftest jieba-rs-tests-segment-region-works ()
  "Segment text in region and show results."
  (with-temp-buffer
    (insert "我们中出了一个叛徒")
    (jieba-rs-mode 1)
    (let ((jieba-rs-hmm nil))
      (jieba-rs-segment-region (point-min) (point-max)))
    (let ((words (with-current-buffer "*jieba-rs-segment*"
                   (buffer-substring-no-properties
                    (point-min) (point-max)))))
      (should (string-match-p "我们" words))
      (should (string-match-p "叛徒" words))
      (should (string-match-p " | " words)))))

(ert-deftest jieba-rs-tests-segment-buffer-works ()
  "Segment text in buffer and show results."
  (with-temp-buffer
    (insert "南京市长江大桥")
    (jieba-rs-mode 1)
    (let ((jieba-rs-hmm nil))
      (jieba-rs-segment-buffer))
    (let ((words (with-current-buffer "*jieba-rs-segment*"
                   (buffer-substring-no-properties
                    (point-min) (point-max)))))
      (should (string-match-p "南京" words))
      (should (string-match-p "长江大桥" words))
      (should (string-match-p " | " words)))))

(ert-deftest jieba-rs-tests-hmm-differs ()
  "Pass the HMM flag through to the native segmentation function."
  (let ((jieba-rs-segment-function 'jieba-rs-module-segment))
    (let ((jieba-rs-hmm nil))
      (should (vectorp (jieba-rs--call-segment "测试"))))
    (let ((jieba-rs-hmm t))
      (should (vectorp (jieba-rs--call-segment "测试"))))))

(ert-deftest jieba-rs-tests-segment-function-differs ()
  "Call dispatch respects jieba-rs-segment-function."
  (let* ((jieba-rs-hmm nil)
         (jieba-rs-segment-function 'jieba-rs-module-segment)
         (precise (jieba-rs--call-segment "测试"))
         (jieba-rs-segment-function 'jieba-rs-module-segment-all)
         (full (jieba-rs--call-segment "测试"))
         (jieba-rs-segment-function 'jieba-rs-module-segment-search)
         (search (jieba-rs--call-segment "测试")))
    (should (vectorp precise))
    (should (vectorp full))
    (should (vectorp search))
    (should-not (equal precise nil))
    (should-not (equal full nil))
    (should-not (equal search nil))))

(ert-deftest jieba-rs-tests-mode-toggle ()
  "Toggle the minor mode on and off correctly."
  (with-temp-buffer
    (should-not jieba-rs-mode)
    (jieba-rs-mode 1)
    (should jieba-rs-mode)
    (jieba-rs-mode -1)
    (should-not jieba-rs-mode)))

(ert-deftest jieba-rs-tests-boundaries-toggle ()
  "Toggle boundaries on and off correctly."
  (with-temp-buffer
    (insert "我们中出了一个叛徒")
    (jieba-rs-mode 1)
    (should-not jieba-rs-boundaries-overlays)
    (jieba-rs-toggle-boundaries)
    (should jieba-rs-boundaries-overlays)
    (jieba-rs-toggle-boundaries)
    (should-not jieba-rs-boundaries-overlays)))

(ert-deftest jieba-rs-tests-boundaries-overlays ()
  "Boundary overlays are created and cleared on edit."
  (with-temp-buffer
    (insert "我们中出了一个叛徒")
    (jieba-rs-mode 1)
    (jieba-rs-toggle-boundaries)
    (should (>= (length jieba-rs-boundaries-overlays) 1))
    (goto-char (point-min))
    (insert "X")
    (should-not jieba-rs-boundaries-overlays)))

(ert-deftest jieba-rs-tests-tags-toggle ()
  "Toggle tags on and off correctly."
  (with-temp-buffer
    (insert "我是中国人")
    (jieba-rs-mode 1)
    (should-not jieba-rs-tag-overlays)
    (jieba-rs-toggle-tags)
    (should jieba-rs-tag-overlays)
    (jieba-rs-toggle-tags)
    (should-not jieba-rs-tag-overlays)))

(ert-deftest jieba-rs-tests-tags-content ()
  "Tag overlays show UD labels and clear on edit."
  (with-temp-buffer
    (insert "我是中国人")
    (jieba-rs-mode 1)
    (jieba-rs-toggle-tags)
    (should (>= (length jieba-rs-tag-overlays) 1))
    (let ((after-str (overlay-get
                      (car jieba-rs-tag-overlays)
                      'after-string)))
      (should (string-match-p
               "pron\\|verb\\|noun\\|propn\\|adj\\|adv"
               after-str)))
    (goto-char (point-min))
    (insert "X")
    (should-not jieba-rs-tag-overlays)))

(ert-deftest jieba-rs-tests-user-dict ()
  "Loading a user dictionary changes segmentation."
  (let ((dict-file (make-temp-file "jieba-rs-test-dict-")))
    (unwind-protect
        (progn
          (with-temp-buffer
            (insert "赛博朋克 100 nz\n")
            (write-region nil nil dict-file nil 'silent))
          (let ((jieba-rs-user-dict dict-file))
            (jieba-rs-mode 1)
            (let ((jieba-rs-hmm nil)
                  (words (jieba-rs-module-segment
                          "我爱赛博朋克" nil)))
              (should (seq-contains-p words
                                      "赛博朋克"))
              (should (= (length words) 3)))))
      (delete-file dict-file))))

(ert-deftest jieba-rs-tests-user-dict-nil ()
  "Without a user dictionary, default segmentation applies."
  (jieba-rs-mode 1)
  (let ((jieba-rs-hmm nil)
        (words (jieba-rs-module-segment "我爱赛博朋克" nil)))
    (should (>= (length words) 3))))

(ert-deftest jieba-rs-tests-add-word ()
  "Adding a word changes segmentation and persists to file."
  (let ((dict-file (make-temp-file "jieba-rs-test-dict-")))
    (unwind-protect
        (let ((jieba-rs-user-dict dict-file)
              (jieba-rs-hmm nil))
          (jieba-rs-mode 1)
          (jieba-rs-add-word "赛博朋克" 100 "nz" t)
          (let ((words (jieba-rs-module-segment
                        "我爱赛博朋克" nil)))
            (should (seq-contains-p words "赛博朋克"))
            (should (= (length words) 3)))
          (with-temp-buffer
            (insert-file-contents dict-file)
            (should (string-match-p
                     "赛博朋克"
                     (buffer-string)))))
      (delete-file dict-file))))

(ert-deftest jieba-rs-tests-forward-word ()
  "Moving forward by Chinese word."
  (with-temp-buffer
    (insert "我们中出了一个叛徒")
    (jieba-rs-mode 1)
    (let ((jieba-rs-hmm nil))
      (goto-char (point-min))
      (jieba-rs-forward-word)
      (should (= (point) 3))
      (jieba-rs-forward-word)
      (should (= (point) 4))
      (jieba-rs-forward-word 3)
      (should (= (point) 8)))))

(ert-deftest jieba-rs-tests-backward-word ()
  "Moving backward by Chinese word."
  (with-temp-buffer
    (insert "我们中出了一个叛徒")
    (jieba-rs-mode 1)
    (let ((jieba-rs-hmm nil))
      (goto-char (point-max))
      (jieba-rs-backward-word)
      (should (= (point) 8))
      (jieba-rs-backward-word)
      (should (= (point) 6)))))

(ert-deftest jieba-rs-tests-forward-sentence ()
  "Moving forward by Chinese sentence."
  (with-temp-buffer
    (insert "你好。世界！")
    (jieba-rs-mode 1)
    (goto-char (point-min))
    (jieba-rs-forward-sentence)
    (should (>= (point) 4))))

(ert-deftest jieba-rs-tests-backward-sentence ()
  "Moving backward by Chinese sentence."
  (with-temp-buffer
    (insert "你好。世界！")
    (jieba-rs-mode 1)
    (goto-char (point-max))
    (jieba-rs-backward-sentence)
    (should (>= (point) 4))))

(ert-deftest jieba-rs-tests-extract-keywords ()
  "TextRank returns keyword plists with :keyword and :weight."
  (jieba-rs-mode 1)
  (let ((kws (jieba-rs-module-extract-keywords
              "南京市长江大桥真的很好玩" 5 "textrank")))
    (should (vectorp kws))
    (should (>= (length kws) 1))
    (let ((first (aref kws 0)))
      (should (plist-member first :keyword))
      (should (plist-member first :weight)))))

(ert-deftest jieba-rs-tests-extract-keywords-textrank-filters-short-words ()
  "TextRank excludes words shorter than the default minimum."
  (let ((kws (jieba-rs-module-extract-keywords
              "今天股票跌很厉害，股票又跌" 100 "textrank")))
    (should (> (length kws) 0))
    (should (seq-every-p
             (lambda (item)
               (>= (length (plist-get item :keyword)) 2))
             kws))))

(ert-deftest jieba-rs-tests-extract-keywords-empty ()
  "TextRank on empty text returns empty vector."
  (jieba-rs-mode 1)
  (let ((kws (jieba-rs-module-extract-keywords "" 5 "textrank")))
    (should (vectorp kws))
    (should (= (length kws) 0))))

(ert-deftest jieba-rs-tests-extract-keywords-tfidf ()
  "TF-IDF returns keyword plists with :keyword and :weight."
  (jieba-rs-mode 1)
  (let ((kws (jieba-rs-module-extract-keywords
              "南京市长江大桥真的很好玩" 5 "tfidf")))
    (should (vectorp kws))
    (should (>= (length kws) 1))
    (let ((first (aref kws 0)))
      (should (plist-member first :keyword))
      (should (plist-member first :weight)))))

(provide 'jieba-rs-tests)
;;; jieba-rs-tests.el ends here
