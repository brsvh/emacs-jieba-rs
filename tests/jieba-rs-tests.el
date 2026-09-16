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
    (should (= (point) 4))))

(ert-deftest jieba-rs-tests-backward-sentence ()
  "Moving backward by Chinese sentence."
  (with-temp-buffer
    (insert "你好。世界！")
    (jieba-rs-mode 1)
    (goto-char (point-max))
    (jieba-rs-backward-sentence)
    (should (= (point) 4))))

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

(ert-deftest jieba-rs-tests-refresh-keeps-source-buffer ()
  "Refresh the source window without modifying the selected buffer."
  (save-window-excursion
    (let ((source (generate-new-buffer " *jieba-source*"))
          (other (generate-new-buffer " *jieba-other*")))
      (unwind-protect
          (progn
            (switch-to-buffer source)
            (insert "我们中出了一个叛徒")
            (let ((source-window (selected-window))
                  (other-window (split-window)))
              (set-window-buffer other-window other)
              (dolist (kind '(boundaries tags))
                (with-current-buffer source
                  (setq jieba-rs--boundaries-enabled t
                        jieba-rs--tags-enabled t)
                  (jieba-rs--schedule-refresh kind source-window)
                  (let ((timer (if (eq kind 'boundaries)
                                   jieba-rs--boundaries-timer
                                 jieba-rs--tags-timer)))
                    (select-window other-window)
                    (unwind-protect
                        (apply (timer--function timer) (timer--args timer))
                      (cancel-timer timer))))
                (with-current-buffer other
                  (should-not jieba-rs-boundaries-overlays)
                  (should-not jieba-rs-tag-overlays)))
              (with-current-buffer source
                (should jieba-rs-boundaries-overlays)
                (should jieba-rs-tag-overlays))))
        (with-current-buffer source
          (jieba-rs--clear-boundaries)
          (jieba-rs--clear-tags))
        (kill-buffer source)
        (kill-buffer other)))))

(ert-deftest jieba-rs-tests-refresh-ignores-dead-buffer ()
  "A pending callback tolerates a killed source buffer."
  (let ((source (generate-new-buffer " *jieba-dead*")))
    (kill-buffer source)
    (jieba-rs--run-refresh source nil #'ignore
                           'jieba-rs--boundaries-timer)))

(ert-deftest jieba-rs-tests-keyword-count-bounds ()
  "Bound huge counts without poisoning subsequent module calls."
  (dolist (method '("tfidf" "textrank"))
    (should (equal (jieba-rs-module-extract-keywords
                    "南京市长江大桥" most-positive-fixnum method)
                   (jieba-rs-module-extract-keywords
                    "南京市长江大桥" 10 method)))
    (should (equal (jieba-rs-module-extract-keywords "" 100 method)
                   []))
    (should (equal (jieba-rs-module-extract-keywords "测试" 0 method)
                   []))
    (should-error (jieba-rs-module-extract-keywords "测试" -1 method)))
  (should (equal (jieba-rs-module-segment "正常测试" nil)
                 ["正常" "测试"])))

(ert-deftest jieba-rs-tests-normalization-selects-mode ()
  "Prefer matching modes over unrelated rules and the fallback."
  (let ((jieba-rs-normalize-rules
         '((t ("a" . " "))
           (org-mode ("." . " "))
           (emacs-lisp-mode ("c" . " "))
           (text-mode ("b" . " ")))))
    (dolist (case '((text-mode . "a c")
                    (emacs-lisp-mode . "ab ")
                    (lisp-interaction-mode . "ab ")
                    (fundamental-mode . " bc")))
      (with-temp-buffer
        (funcall (car case))
        (insert "abc")
        (should (equal (jieba-rs--normalize-text (point-min) (point-max))
                       (cdr case)))))))

(ert-deftest jieba-rs-tests-sentence-boundaries ()
  "Handle unterminated sentences, counts, narrowing and both ends."
  (with-temp-buffer
    (insert "你好。  世界！\n没有句号")
    (goto-char (point-min))
    (jieba-rs-forward-sentence 3)
    (should (= (point) (point-max)))
    (jieba-rs-forward-sentence)
    (should (= (point) (point-max)))
    (jieba-rs-backward-sentence)
    (should (looking-at-p "没有句号"))
    (jieba-rs-forward-sentence -1)
    (should (looking-at-p "世界"))
    (jieba-rs-backward-sentence 2)
    (should (= (point) (point-min)))
    (jieba-rs-backward-sentence -1)
    (should (= (point) 4))
    (narrow-to-region 10 (point-max))
    (goto-char (point-min))
    (jieba-rs-forward-sentence)
    (should (= (point) (point-max)))
    (jieba-rs-backward-sentence)
    (should (= (point) (point-min)))))

(ert-deftest jieba-rs-tests-tags-include-final-word ()
  "Display the final word tag with or without trailing whitespace."
  (dolist (text '("中国" "中国\n" "中国  "))
    (with-temp-buffer
      (insert text)
      (unwind-protect
          (progn
            (jieba-rs-toggle-tags)
            (should (= (length jieba-rs-tag-overlays) 1))
            (should (= (overlay-start (car jieba-rs-tag-overlays)) 3)))
        (jieba-rs--clear-tags)))))

(ert-deftest jieba-rs-tests-display-state-independent-of-overlays ()
  "Disable empty displays and displays waiting for a refresh."
  (with-temp-buffer
    (jieba-rs-toggle-boundaries)
    (jieba-rs-toggle-tags)
    (should jieba-rs--boundaries-enabled)
    (should jieba-rs--tags-enabled)
    (should-not jieba-rs-boundaries-overlays)
    (should-not jieba-rs-tag-overlays)
    (jieba-rs-toggle-boundaries)
    (jieba-rs-toggle-tags)
    (should-not jieba-rs--boundaries-enabled)
    (should-not jieba-rs--tags-enabled)
    (should-not (memq #'jieba-rs--tags-after-change after-change-functions))
    (insert "我们中出了一个叛徒")
    (jieba-rs-toggle-boundaries)
    (jieba-rs-toggle-tags)
    (insert "！")
    (should jieba-rs--boundaries-timer)
    (should jieba-rs--tags-timer)
    (jieba-rs-mode -1)
    (should-not jieba-rs--boundaries-enabled)
    (should-not jieba-rs--tags-enabled)
    (should-not jieba-rs--boundaries-timer)
    (should-not jieba-rs--tags-timer)
    (should-not (memq #'jieba-rs--post-command-scroll-check post-command-hook))))

(ert-deftest jieba-rs-tests-empty-display-scroll-refresh ()
  "Schedule scroll refreshes even when there are no overlays."
  (with-temp-buffer
    (unwind-protect
        (progn
          (jieba-rs-toggle-boundaries)
          (jieba-rs-toggle-tags)
          (jieba-rs--boundaries-window-scroll (selected-window) 1)
          (jieba-rs--tags-window-scroll (selected-window) 1)
          (should jieba-rs--boundaries-timer)
          (should jieba-rs--tags-timer))
      (jieba-rs--clear-display))))

(ert-deftest jieba-rs-tests-kill-buffer-cancels-display-timers ()
  "Remove pending timers when their buffer is killed."
  (let ((buffer (generate-new-buffer " *jieba-timers*"))
        boundary-timer tag-timer)
    (with-current-buffer buffer
      (jieba-rs-toggle-boundaries)
      (jieba-rs-toggle-tags)
      (insert "测试")
      (setq boundary-timer jieba-rs--boundaries-timer
            tag-timer jieba-rs--tags-timer))
    (kill-buffer buffer)
    (should-not (memq boundary-timer timer-idle-list))
    (should-not (memq tag-timer timer-idle-list))))

(ert-deftest jieba-rs-tests-persist-separates-records ()
  "Keep records separate in empty and unterminated dictionaries."
  (dolist (initial '("" "甲乙 10 nz" "甲乙 10 nz\n"))
    (let ((jieba-rs-user-dict (make-temp-file "jieba-records-")))
      (unwind-protect
          (progn
            (with-temp-file jieba-rs-user-dict (insert initial))
            (jieba-rs-add-word "审查临时测试词" 100 "nz" t)
            (with-temp-buffer
              (insert-file-contents jieba-rs-user-dict)
              (should (equal (buffer-string)
                             (concat (if (string-empty-p initial) ""
                                       "甲乙 10 nz\n")
                                     "审查临时测试词 100 nz\n"))))
            (jieba-rs-module-load-user-dict jieba-rs-user-dict))
        (delete-file jieba-rs-user-dict)))))

(ert-deftest jieba-rs-tests-invalid-persistence-does-not-add-word ()
  "Reject invalid persistence settings before changing the dictionary."
  (cl-letf (((symbol-function 'jieba-rs-module-add-word)
             (lambda (&rest _) (ert-fail "Dictionary was modified"))))
    (let ((jieba-rs-user-dict nil))
      (should-error (jieba-rs-add-word "测试" 100 nil t) :type 'user-error))
    (let ((jieba-rs-user-dict "/unused/dictionary"))
      (dolist (word '("" "两个 词" "两行\n词"))
        (should-error (jieba-rs-add-word word 100 nil t) :type 'user-error))
      (should-error (jieba-rs-add-word "测试" 100 "n x" t)
                    :type 'user-error))))

(ert-deftest jieba-rs-tests-update-existing-word-tag ()
  "Apply explicit tags to existing words and retain them when omitted."
  (jieba-rs-module-add-word "词性覆盖测试词" 100 "old")
  (jieba-rs-module-add-word "词性覆盖测试词" 100 "custom")
  (should (equal (plist-get (aref (jieba-rs-module-segment-tag
                                   "词性覆盖测试词" nil) 0) :category)
                 "custom"))
  (jieba-rs-module-add-word "词性覆盖测试词" 100 nil)
  (should (equal (plist-get (aref (jieba-rs-module-segment-tag
                                   "词性覆盖测试词" nil) 0) :category)
                 "custom")))

(ert-deftest jieba-rs-tests-user-dict-overrides-existing-tag ()
  "Apply the last dictionary tag to an already known word."
  (let ((file (make-temp-file "jieba-tags-")))
    (unwind-protect
        (progn
          (jieba-rs-module-add-word "词典词性测试词" 100 "old")
          (with-temp-file file
            (insert "词典词性测试词 100 first\n词典词性测试词 100 last\n"))
          (jieba-rs-module-load-user-dict file)
          (should (equal (plist-get (aref (jieba-rs-module-segment-tag
                                           "词典词性测试词" nil) 0) :category)
                         "last")))
      (delete-file file))))

(ert-deftest jieba-rs-tests-tfidf-reuses-current-dictionary ()
  "A reused extractor observes words added after its initialization."
  (jieba-rs-module-extract-keywords "关键词缓存测试词" 5 "tfidf")
  (jieba-rs-module-add-word "关键词缓存测试词" 100 "n")
  (let ((result (jieba-rs-module-extract-keywords
                 "关键词缓存测试词" 5 "tfidf")))
    (should (equal (plist-get (aref result 0) :keyword)
                   "关键词缓存测试词"))
    (should (equal result (jieba-rs-module-extract-keywords
                           "关键词缓存测试词" 5 "tfidf")))))

(ert-deftest jieba-rs-tests-word-motion-across-lines ()
  "Move across blank lines, partial words and narrowed boundaries."
  (with-temp-buffer
    (insert "我们\n \n中国\n")
    (let ((jieba-rs-hmm nil))
      (goto-char 1)
      (jieba-rs-forward-word)
      (should (= (point) 3))
      (jieba-rs-forward-word)
      (should (= (point) 8))
      (jieba-rs-backward-word)
      (should (= (point) 6))
      (jieba-rs-backward-word)
      (should (= (point) 1))
      (jieba-rs-forward-word 10)
      (should (= (point) (point-max)))
      (jieba-rs-forward-word -10)
      (should (= (point) (point-min)))
      (narrow-to-region 6 8)
      (goto-char 7)
      (jieba-rs-forward-word)
      (should (= (point) 8))
      (jieba-rs-backward-word)
      (should (= (point) 6))
      (jieba-rs-backward-word -1)
      (should (= (point) 8))
      (jieba-rs-forward-word 0)
      (should (= (point) 8)))))

(ert-deftest jieba-rs-tests-word-motion-reuses-line ()
  "Repeated motion segments a long line only once."
  (with-temp-buffer
    (insert (apply #'concat (make-list 1000 "南京市长江大桥 ")))
    (goto-char (point-min))
    (let ((original (symbol-function 'jieba-rs-module-segment))
          (calls 0))
      (cl-letf (((symbol-function 'jieba-rs-module-segment)
                 (lambda (text hmm)
                   (setq calls (1+ calls))
                   (funcall original text hmm))))
        (jieba-rs-forward-word 10)
        (jieba-rs-backward-word 10)
        (should (= (point) (point-min)))
        (should (= calls 1))))))

(ert-deftest jieba-rs-tests-refresh-segments-visible-lines ()
  "Refresh only visible lines and reuse them without editing."
  (with-temp-buffer
    (insert (apply #'concat (make-list 10000 "我们中出了一个叛徒。\n")))
    (let ((segment (symbol-function 'jieba-rs-module-segment))
          (tag (symbol-function 'jieba-rs-module-segment-tag))
          (characters 0))
      (cl-letf (((symbol-function 'jieba-rs--visible-range)
                 (lambda () (cons 1 45)))
                ((symbol-function 'jieba-rs-module-segment)
                 (lambda (text hmm)
                   (setq characters (+ characters (length text)))
                   (funcall segment text hmm)))
                ((symbol-function 'jieba-rs-module-segment-tag)
                 (lambda (text hmm)
                   (setq characters (+ characters (length text)))
                   (funcall tag text hmm))))
        (unwind-protect
            (progn
              (jieba-rs-toggle-boundaries)
              (jieba-rs-toggle-tags)
              (should (< characters 150))
              (let ((initial characters))
                (jieba-rs--refresh-boundaries)
                (jieba-rs--refresh-tags)
                (should (= characters initial))))
          (jieba-rs--clear-display))))))

(ert-deftest jieba-rs-tests-cache-observes-dictionary-updates ()
  "Invalidate cached lines after a dictionary update in another buffer."
  (with-temp-buffer
    (insert "分词缓存失效测试词")
    (let ((jieba-rs-hmm nil))
      (should (> (length (aref (jieba-rs--line-tokens 1) 2)) 1))
      (with-temp-buffer
        (jieba-rs-module-add-word "分词缓存失效测试词" 100 "n"))
      (should (= (length (aref (jieba-rs--line-tokens 1) 2)) 1))
      (goto-char 1)
      (jieba-rs-forward-word)
      (should (= (point) (point-max))))))

(ert-deftest jieba-rs-tests-cache-observes-text-and-rules ()
  "Invalidate cached results after text, rules or narrowing change."
  (with-temp-buffer
    (insert "我们")
    (should (equal (aref (aref (aref (jieba-rs--line-tokens 1 nil t) 2) 0) 2)
                   "我们"))
    (erase-buffer)
    (insert "中国")
    (should (equal (aref (aref (aref (jieba-rs--line-tokens 1 nil t) 2) 0) 2)
                   "中国"))
    (let ((jieba-rs-normalize-rules '((t ("." . " ")))))
      (should (string-blank-p
               (aref (aref (aref (jieba-rs--line-tokens 1 nil t) 2) 0) 2))))
    (narrow-to-region 2 3)
    (should (equal (aref (aref (aref (jieba-rs--line-tokens 2) 2) 0) 2)
                   "国"))))

(ert-deftest jieba-rs-tests-cache-observes-hmm-option ()
  "Use new word boundaries when HMM is changed."
  (with-temp-buffer
    (insert "杭研大厦")
    (goto-char 1)
    (let ((jieba-rs-hmm nil))
      (jieba-rs-forward-word)
      (should (= (point) 2)))
    (goto-char 1)
    (let ((jieba-rs-hmm t))
      (jieba-rs-forward-word)
      (should (= (point) 3)))))

(ert-deftest jieba-rs-tests-cache-observes-dictionary-file ()
  "Use new boundaries after loading a dictionary file."
  (let ((file (make-temp-file "jieba-cache-dict-")))
    (unwind-protect
        (with-temp-buffer
          (insert "文件缓存更新测试词")
          (should (> (length (aref (jieba-rs--line-tokens 1) 2)) 1))
          (with-temp-file file
            (insert "文件缓存更新测试词 100 n\n"))
          (jieba-rs-module-load-user-dict file)
          (goto-char 1)
          (jieba-rs-forward-word)
          (should (= (point) (point-max))))
      (delete-file file))))

(ert-deftest jieba-rs-tests-reject-invalid-string-bytes ()
  "Reject invalid UTF-8 at every native string boundary without panicking."
  (let ((invalid (unibyte-string #xff))
        (version (jieba-rs-module-dictionary-version)))
    (dolist (call `((jieba-rs-module-segment ,invalid nil)
                    (jieba-rs-module-segment-all ,invalid)
                    (jieba-rs-module-segment-search ,invalid nil)
                    (jieba-rs-module-segment-tag ,invalid nil)
                    (jieba-rs-module-load-user-dict ,invalid)
                    (jieba-rs-module-add-word ,invalid 100 nil)
                    (jieba-rs-module-add-word "测试" 100 ,invalid)
                    (jieba-rs-module-extract-keywords ,invalid 5 "tfidf")
                    (jieba-rs-module-extract-keywords "测试" 5 ,invalid)))
      (should-error (apply (car call) (cdr call))
                    :type 'wrong-type-argument))
    (should (= version (jieba-rs-module-dictionary-version)))
    (should (equal (jieba-rs-module-segment "中国" nil) ["中国"]))))

(ert-deftest jieba-rs-tests-preserve-string-contents ()
  "Keep Unicode and NUL characters intact during native conversion."
  (dolist (text '("" "ASCII" "中国😀" "\0" "中国\0\0" "中国\0北京"))
    (should (equal (mapconcat #'identity
                              (jieba-rs-module-segment text nil) "")
                   text))
    (let ((tags (jieba-rs-module-segment-tag text nil)))
      (should (equal (mapconcat (lambda (tag) (plist-get tag :word))
                                tags "")
                     text))
      (when (> (length tags) 0)
        (should (= (plist-get (aref tags (1- (length tags))) :end)
                   (length text)))))))

(ert-deftest jieba-rs-tests-dictionary-load-is-atomic ()
  "A failed load leaves frequencies, tags and the cache version intact."
  (let ((file (make-temp-file "jieba-atomic-dict-"))
        (text "南京市长江大桥研究生命起源"))
    (unwind-protect
        (progn
          (jieba-rs-module-add-word "事务词典既有词" 100 "old")
          (let ((version (jieba-rs-module-dictionary-version))
                (before (jieba-rs-module-segment text nil))
                (tags (jieba-rs-module-segment-tag "事务词典既有词" nil)))
            (with-temp-file file
              (insert "事务词典既有词 0 new\n"
                      "南京市长江大桥 100000000 ns\n错误 invalid n\n"))
            (should-error (jieba-rs-module-load-user-dict file))
            (should (= version (jieba-rs-module-dictionary-version)))
            (should (equal before (jieba-rs-module-segment text nil)))
            (should (equal tags (jieba-rs-module-segment-tag
                                 "事务词典既有词" nil)))
            (jieba-rs-module-add-word "事务之后新词" 1 nil)
            (should (equal before (jieba-rs-module-segment text nil))))
          (with-temp-file file (insert "事务词典既有词 100 new\n"))
          (let ((version (jieba-rs-module-dictionary-version)))
            (jieba-rs-module-load-user-dict file)
            (should (= (1+ version) (jieba-rs-module-dictionary-version))))
          (should (equal (plist-get (aref (jieba-rs-module-segment-tag
                                           "事务词典既有词" nil) 0)
                                    :category)
                         "new")))
      (delete-file file))))

(ert-deftest jieba-rs-tests-major-mode-clears-display ()
  "Remove overlays and timers before a major mode resets local state."
  (with-temp-buffer
    (insert "我们中出了一个叛徒")
    (jieba-rs-toggle-boundaries)
    (jieba-rs-toggle-tags)
    (jieba-rs--schedule-refresh 'boundaries)
    (jieba-rs--schedule-refresh 'tags)
    (let ((overlays (append jieba-rs-boundaries-overlays
                            jieba-rs-tag-overlays))
          (boundary-timer jieba-rs--boundaries-timer)
          (tag-timer jieba-rs--tags-timer))
      (should overlays)
      (text-mode)
      (should-not (seq-some #'overlay-buffer overlays))
      (should-not (memq boundary-timer timer-idle-list))
      (should-not (memq tag-timer timer-idle-list))
      (should-not jieba-rs--boundaries-enabled)
      (should-not jieba-rs--tags-enabled)
      (jieba-rs-toggle-tags)
      (should jieba-rs-tag-overlays)
      (jieba-rs-mode -1)
      (should-not (memq #'jieba-rs--clear-display change-major-mode-hook)))))

(ert-deftest jieba-rs-tests-backward-sentence-leading-whitespace ()
  "Reach the accessible beginning instead of advancing through whitespace."
  (dolist (text '("   " "   你好。" "\t　你好。"))
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (skip-chars-forward " \t　")
      (let ((first-word (point)))
        (dotimes (offset first-word)
          (dolist (command '(jieba-rs-backward-sentence
                             jieba-rs-forward-sentence))
            (goto-char (1+ offset))
            (funcall command (if (eq command 'jieba-rs-forward-sentence)
                                 -1 1))
            (should (= (point) (point-min))))))))
  (with-temp-buffer
    (insert "前缀\n   你好。")
    (narrow-to-region 4 (point-max))
    (goto-char 5)
    (jieba-rs-backward-sentence 2)
    (should (= (point) (point-min)))
    (goto-char (point-max))
    (jieba-rs-backward-sentence)
    (should (looking-at-p "你好"))
    (jieba-rs-backward-sentence)
    (should (= (point) (point-min)))))

(ert-deftest jieba-rs-tests-refresh-skips-offscreen-tokens ()
  "Inspect only visible tokens when refreshing a cached long line."
  (with-temp-buffer
    (insert (apply #'concat (make-list 10000 "我们中国 ")))
    (dolist (tagged '(nil t))
      (jieba-rs--line-tokens 1 tagged t)
      (let ((blank-p (symbol-function 'string-blank-p))
            (checks 0)
            positions)
        (cl-letf (((symbol-function 'jieba-rs--visible-range)
                   (lambda () '(25003 . 25018)))
                  ((symbol-function 'string-blank-p)
                   (lambda (text)
                     (setq checks (1+ checks))
                     (funcall blank-p text))))
          (jieba-rs--map-visible-tokens
           (lambda (token) (push (aref token 1) positions)) tagged))
        (should (equal (nreverse positions)
                       (append '(25003 25005 25008 25010 25013 25015)
                               (when tagged '(25018)))))
        (should (< checks 12))))))

(ert-deftest jieba-rs-tests-cache-retains-visible-working-set ()
  "Keep both displays cached beyond the original fixed entry limit."
  (dolist (lines '(65 129))
    (with-temp-buffer
      (insert (apply #'concat (make-list lines "测试\n")))
      (dolist (tagged '(nil t))
        (jieba-rs--map-visible-tokens #'ignore tagged))
      (cl-letf (((symbol-function 'jieba-rs-module-segment)
                 (lambda (&rest _) (ert-fail "Boundary cache miss")))
                ((symbol-function 'jieba-rs-module-segment-tag)
                 (lambda (&rest _) (ert-fail "Tag cache miss"))))
        (dolist (tagged '(nil t))
          (jieba-rs--map-visible-tokens #'ignore tagged)))
      (cl-letf (((symbol-function 'jieba-rs--visible-range)
                 (lambda () '(1 . 4))))
        (jieba-rs--map-visible-tokens #'ignore))
      (should (<= (hash-table-count jieba-rs--segment-cache) 128)))))

(ert-deftest jieba-rs-tests-cache-evicts-least-recently-used ()
  "Retain a frequently visited line while bounding offscreen results."
  (with-temp-buffer
    (insert (apply #'concat (make-list 200 "测试\n")))
    (let ((recent (jieba-rs--line-tokens 1)))
      (dotimes (index 199)
        (jieba-rs--line-tokens (+ 4 (* 3 index)))
        (should (eq recent (jieba-rs--line-tokens 1))))
      (should (= (hash-table-count jieba-rs--segment-cache) 128)))))

(provide 'jieba-rs-tests)
;;; jieba-rs-tests.el ends here
