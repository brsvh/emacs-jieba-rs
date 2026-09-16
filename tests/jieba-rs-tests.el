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

(defun jieba-rs-tests--run-native-child (form)
  "Evaluate FORM in a fresh module process, failing after 15 seconds."
  (with-temp-buffer
    (let* ((process
            (make-process
             :name "jieba-rs-test" :buffer (current-buffer)
             :connection-type 'pipe :noquery t :sentinel #'ignore
             :command
             (list (expand-file-name invocation-name invocation-directory)
                   "-Q" "--batch"
                   "-l" (locate-library "jieba-rs-module")
                   "--eval" (let ((print-escape-control-characters t))
                              (prin1-to-string form)))))
           (deadline (+ (float-time) 15)))
      (unwind-protect
          (progn
            (while (and (process-live-p process)
                        (< (float-time) deadline))
              (accept-process-output process 0.05))
            (should-not (process-live-p process))
            (should (equal (list (process-exit-status process)
                                 (buffer-string))
                           '(0 "ok"))))
        (when (process-live-p process)
          (delete-process process))))))

(ert-deftest jieba-rs-tests-reject-nul-dictionary-words ()
  "Reject NUL keys without modifying or poisoning the shared dictionary."
  (jieba-rs-tests--run-native-child
   '(progn
      (require 'ert)
      (let ((file (make-temp-file "jieba-nul-")))
        (unwind-protect
            (progn
              (jieba-rs-module-add-word "词典完整性测试词" 100 "old")
              (let ((version (jieba-rs-module-dictionary-version))
                    (before (jieba-rs-module-segment "中国北京" nil))
                    (tags (jieba-rs-module-segment-tag "词典完整性测试词" nil)))
                (dolist (word '("\0" "中国\0" "\0中国" "中国\0北京"))
                  (should-error (jieba-rs-module-add-word word nil "new")
                                :type 'rust-error)
                  (with-temp-file file
                    (insert "词典完整性测试词 1 changed\n"
                            word " 100 n\n"))
                  (should-error (jieba-rs-module-load-user-dict file)
                                :type 'rust-error)
                  (should (= version (jieba-rs-module-dictionary-version)))
                  (should (equal before (jieba-rs-module-segment "中国北京" nil)))
                  (should (equal tags (jieba-rs-module-segment-tag
                                       "词典完整性测试词" nil)))))
              (jieba-rs-module-add-word "后续正常添加词" 100 "n")
              (should (equal (jieba-rs-module-segment "后续正常添加词" nil)
                             ["后续正常添加词"])))
          (delete-file file)))
      (princ "ok"))))

(ert-deftest jieba-rs-tests-gc-can-reenter-native-module ()
  "Allow GC hooks to query the dictionary while creating results."
  (dolist (operation '(jieba-rs-module-segment-tag
                       jieba-rs-module-extract-keywords))
    (jieba-rs-tests--run-native-child
     `(let ((text (mapconcat (lambda (i) (format "token%d" i))
                             (number-sequence 1 500) " "))
            (calls 0))
        (jieba-rs-module-segment "warmup" nil)
        (garbage-collect)
        (let ((gc-cons-threshold 1000)
              (gc-cons-percentage 0.0)
              (post-gc-hook
               (list (lambda ()
                       (setq gc-cons-threshold most-positive-fixnum)
                       (jieba-rs-module-dictionary-version)
                       (setq calls (1+ calls))))))
          ,(if (eq operation 'jieba-rs-module-segment-tag)
               '(jieba-rs-module-segment-tag text nil)
             '(jieba-rs-module-extract-keywords text 500 "tfidf")))
        (unless (> calls 0) (error "GC hook was not exercised"))
        (princ "ok")))))

(ert-deftest jieba-rs-tests-reject-excessive-dictionary-frequencies ()
  "Reject individual and cumulative frequency excess without mutation."
  (jieba-rs-tests--run-native-child
   '(progn
      (require 'ert)
      (let ((file (make-temp-file "jieba-frequency-")))
        (unwind-protect
            (progn
              (jieba-rs-module-add-word "审查词甲" most-positive-fixnum "nz")
              (jieba-rs-module-add-word "审查词乙" most-positive-fixnum "nz")
              (let ((version (jieba-rs-module-dictionary-version))
                    (words (jieba-rs-module-segment "我们中出了一个叛徒" nil))
                    (tags (jieba-rs-module-segment-tag "审查词甲" nil)))
                (dolist (frequency (list 2 (1- (expt 2 63))))
                  (should-error
                   (jieba-rs-module-add-word "审查词丙" frequency "new"))
                  (with-temp-file file
                    (insert (format "审查词甲 %d changed\n审查词丙 %d nz\n"
                                    most-positive-fixnum frequency)))
                  (should-error (jieba-rs-module-load-user-dict file))
                  (should (= version (jieba-rs-module-dictionary-version)))
                  (should (equal words (jieba-rs-module-segment
                                        "我们中出了一个叛徒" nil)))
                  (should (equal tags (jieba-rs-module-segment-tag
                                       "审查词甲" nil)))))
              ;; Replacing the same record must not consume more budget.
              (jieba-rs-module-add-word "审查词甲" most-positive-fixnum nil))
          (delete-file file)))
      (princ "ok"))))

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
  (dolist (jieba-rs-segment-function '(jieba-rs-module-segment
                                       jieba-rs-module-segment-search))
    (cl-letf (((symbol-function jieba-rs-segment-function)
               (lambda (text hmm) (vector text hmm))))
      (dolist (jieba-rs-hmm '(nil t))
        (should (equal (jieba-rs--call-segment "测试")
                       (vector "测试" jieba-rs-hmm)))))))

(ert-deftest jieba-rs-tests-segment-function-differs ()
  "Call dispatch respects jieba-rs-segment-function."
  (let* ((jieba-rs-hmm nil)
         (jieba-rs-segment-function 'jieba-rs-module-segment)
         (precise (jieba-rs--call-segment "南京市长江大桥"))
         (jieba-rs-segment-function 'jieba-rs-module-segment-all)
         (full (jieba-rs--call-segment "南京市长江大桥"))
         (jieba-rs-segment-function 'jieba-rs-module-segment-search)
         (search (jieba-rs--call-segment "南京市长江大桥")))
    (should (equal precise ["南京市" "长江大桥"]))
    (should (seq-contains-p full "南京"))
    (should (seq-contains-p search "长江"))
    (should-not (equal precise full))
    (should-not (equal precise search))))

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

(ert-deftest jieba-rs-tests-user-dict-reuses-unchanged-file ()
  "Share successful loads across buffers and alternate file names."
  (let* ((directory (make-temp-file "jieba-dict-cache-" t))
         (jieba-rs-user-dict (expand-file-name "dict" directory))
         (alias (expand-file-name "alias" directory))
         (jieba-rs--loaded-user-dicts (make-hash-table :test #'equal))
         (version (jieba-rs-module-dictionary-version)))
    (unwind-protect
        (progn
          (with-temp-file jieba-rs-user-dict (insert "自动加载缓存词 100 file\n"))
          (make-symbolic-link jieba-rs-user-dict alias)
          (dotimes (_ 3)
            (with-temp-buffer (jieba-rs-mode 1)))
          (let ((jieba-rs-user-dict alias))
            (with-temp-buffer (jieba-rs-mode 1)))
          (should (= (1+ version) (jieba-rs-module-dictionary-version)))
          (jieba-rs-module-add-word "自动加载缓存词" 100 "session")
          (jieba-rs--load-user-dict)
          (should (equal (plist-get (aref (jieba-rs-module-segment-tag
                                           "自动加载缓存词" nil) 0) :category)
                         "session"))
          (jieba-rs-reload-user-dict)
          (should (= (+ version 3) (jieba-rs-module-dictionary-version)))
          (should (equal (plist-get (aref (jieba-rs-module-segment-tag
                                           "自动加载缓存词" nil) 0) :category)
                         "file"))
          (with-temp-file jieba-rs-user-dict
            (insert "自动加载缓存词 100 changed\n"))
          (jieba-rs--load-user-dict)
          (should (= (+ version 4) (jieba-rs-module-dictionary-version)))
          (should (equal (plist-get (aref (jieba-rs-module-segment-tag
                                           "自动加载缓存词" nil) 0) :category)
                         "changed")))
      (delete-directory directory t))))

(ert-deftest jieba-rs-tests-user-dict-retries-failed-load ()
  "Cache a dictionary only after a successful load."
  (let ((jieba-rs-user-dict (make-temp-file "jieba-dict-retry-"))
        (jieba-rs--loaded-user-dicts (make-hash-table :test #'equal))
        (load (symbol-function 'jieba-rs-module-load-user-dict))
        (calls 0))
    (unwind-protect
        (cl-letf (((symbol-function 'jieba-rs-module-load-user-dict)
                   (lambda (file)
                     (cl-incf calls)
                     (if (= calls 1) (error "Temporary read failure")
                       (funcall load file))))
                  ((symbol-function 'display-warning) #'ignore))
          (jieba-rs--load-user-dict)
          (should (= (hash-table-count jieba-rs--loaded-user-dicts) 0))
          (jieba-rs--load-user-dict)
          (jieba-rs--load-user-dict)
          (should (= calls 2))
          (should (= (hash-table-count jieba-rs--loaded-user-dicts) 1)))
      (delete-file jieba-rs-user-dict))))

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

(ert-deftest jieba-rs-tests-dictionary-refreshes-enabled-displays ()
  "Refresh both displays in all shown buffers after dictionary changes."
  (save-window-excursion
    (let ((buffers (list (generate-new-buffer " *jieba-dict-a*")
                         (generate-new-buffer " *jieba-dict-b*")))
          (jieba-rs-user-dict (make-temp-file "jieba-display-dict-"))
          (jieba-rs--loaded-user-dicts (make-hash-table :test #'equal))
          (jieba-rs-hmm nil)
          (word "共享显示刷新回归词"))
      (unwind-protect
          (progn
            (jieba-rs-module-add-word word 0 "old")
            (switch-to-buffer (car buffers))
            (set-window-buffer (split-window-below) (cadr buffers))
            (dolist (buffer buffers)
              (with-current-buffer buffer
                (insert word)
                (jieba-rs-toggle-boundaries)
                (jieba-rs-toggle-tags)
                (should jieba-rs-boundaries-overlays)))
            (dolist (operation '(add reload failed-save))
              (pcase operation
                ('add (jieba-rs-add-word word 1000 "updated"))
                ('reload
                 (with-temp-file jieba-rs-user-dict
                   (insert word " 1000 updated\n"))
                 (jieba-rs-reload-user-dict))
                ('failed-save
                 (cl-letf (((symbol-function 'jieba-rs--append-word)
                            (lambda (&rest _) (error "Cannot save"))))
                   (should-error (jieba-rs-add-word word 1000 "updated" t)))))
              (dolist (buffer buffers)
                (with-current-buffer buffer
                  (should-not jieba-rs-boundaries-overlays)
                  (should-not jieba-rs-tag-overlays)
                  (should jieba-rs--boundaries-timer)
                  (should jieba-rs--tags-timer)
                  (dolist (timer (list jieba-rs--boundaries-timer
                                       jieba-rs--tags-timer))
                    (apply (timer--function timer) (timer--args timer)))
                  (should-not jieba-rs-boundaries-overlays)
                  (should (= (length jieba-rs-tag-overlays) 1))
                  (should (equal (overlay-get (car jieba-rs-tag-overlays)
                                              'after-string)
                                 "updated")))))
            (should-error (jieba-rs-add-word word -1 "failed"))
            (with-temp-file jieba-rs-user-dict (insert "bad invalid n\n"))
            (should-error (jieba-rs-reload-user-dict))
            (dolist (buffer buffers)
              (with-current-buffer buffer
                (should-not jieba-rs--boundaries-timer)
                (should-not jieba-rs--tags-timer)
                (should (= (length jieba-rs-tag-overlays) 1)))))
        (mapc #'kill-buffer buffers)
        (delete-file jieba-rs-user-dict)))))

(ert-deftest jieba-rs-tests-refresh-preserves-other-windows ()
  "Keep disjoint views, merge overlaps, and tolerate a closed window."
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (insert (apply #'concat (make-list 300 "中国\n")))
      (goto-char 1)
      (let ((first (selected-window))
            (second (split-window-below)))
        (set-window-buffer second (current-buffer))
        (set-window-start first 1)
        ;; Batch Emacs does not redisplay; model two twenty-line views.
        (cl-letf (((symbol-function 'window-end)
                   (lambda (window &optional _update)
                     (+ 60 (window-start window)))))
          (dolist (kind '(boundaries tags))
            (set-window-start second 301)
            (funcall (if (eq kind 'boundaries)
                         #'jieba-rs-toggle-boundaries #'jieba-rs-toggle-tags))
            (should (= (length (overlays-in 1 61)) 20))
            (should (= (length (overlays-in 301 361)) 20))
            (set-window-start second 601)
            (jieba-rs--schedule-refresh kind second)
            (let ((timer (if (eq kind 'boundaries)
                             jieba-rs--boundaries-timer jieba-rs--tags-timer)))
              (apply (timer--function timer) (timer--args timer)))
            (should (eq (selected-window) first))
            (should (= (length (overlays-in 1 61)) 20))
            (should-not (overlays-in 301 361))
            (should (= (length (overlays-in 601 661)) 20))
            (set-window-start second 31)
            (funcall (if (eq kind 'boundaries)
                         #'jieba-rs--refresh-boundaries #'jieba-rs--refresh-tags))
            (let ((positions (mapcar #'overlay-start (overlays-in 1 91))))
              (should (= (length positions) 30))
              (should (= (length (delete-dups positions)) 30)))
            (jieba-rs--clear-display))
          (jieba-rs-toggle-boundaries)
          (jieba-rs--schedule-refresh 'boundaries second)
          (let ((timer jieba-rs--boundaries-timer))
            (delete-window second)
            (apply (timer--function timer) (timer--args timer)))
          (should (= (length jieba-rs-boundaries-overlays) 20)))))))

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
    (should-error (jieba-rs-module-extract-keywords "测试" -1 method))
    (should-error (jieba-rs-module-extract-keywords "" -1 method)))
  (dolist (text '("测试" ""))
    (should-error (jieba-rs-module-extract-keywords text 0 123)
                  :type 'wrong-type-argument))
  (should-error (jieba-rs-module-extract-keywords (string #x3fff80) 0 "tfidf")
                :type 'wrong-type-argument)
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

(ert-deftest jieba-rs-tests-clone-owns-display-state ()
  "Keep cloned overlays and caches independent through either cleanup."
  (dolist (cleanup '(disable kill major-mode))
    (with-temp-buffer
      (insert "中国北京\n")
      (jieba-rs-toggle-boundaries)
      (jieba-rs-toggle-tags)
      (let* ((source (current-buffer))
             (overlays (append jieba-rs-boundaries-overlays jieba-rs-tag-overlays))
             (cache jieba-rs--segment-cache)
             (clone (clone-indirect-buffer " *jieba-clone*" nil)))
        (unwind-protect
            (progn
              (with-current-buffer clone
                (should jieba-rs--boundaries-enabled)
                (should jieba-rs--tags-enabled)
                (should-not jieba-rs-boundaries-overlays)
                (should-not jieba-rs-tag-overlays)
                (should-not jieba-rs--segment-cache)
                (jieba-rs--refresh-boundaries)
                (jieba-rs--refresh-tags)
                (should-not (eq cache jieba-rs--segment-cache))
                (dolist (overlay (append jieba-rs-boundaries-overlays
                                         jieba-rs-tag-overlays))
                  (should (eq (overlay-buffer overlay) clone))))
              (pcase cleanup
                ('disable (with-current-buffer clone (jieba-rs-mode -1)))
                ('kill (kill-buffer clone))
                ('major-mode (with-current-buffer clone (text-mode))))
              (dolist (overlay overlays)
                (should (eq (overlay-buffer overlay) source)))
              ;; Clearing the source must likewise leave a rebuilt clone alone.
              (when (buffer-live-p clone)
                (with-current-buffer clone (jieba-rs--show-tags))
                (jieba-rs-mode -1)
                (with-current-buffer clone
                  (should jieba-rs-tag-overlays)
                  (dolist (overlay jieba-rs-tag-overlays)
                    (should (eq (overlay-buffer overlay) clone))))))
          (when (buffer-live-p clone) (kill-buffer clone)))))))

(ert-deftest jieba-rs-tests-clone-preserves-source-timers ()
  "Do not cancel source refreshes when cleaning up a new clone."
  (with-temp-buffer
    (insert "中国北京\n")
    (jieba-rs-toggle-boundaries)
    (jieba-rs-toggle-tags)
    (jieba-rs--schedule-refresh 'boundaries)
    (jieba-rs--schedule-refresh 'tags)
    (let* ((boundary-timer jieba-rs--boundaries-timer)
           (tag-timer jieba-rs--tags-timer)
           (clone (clone-indirect-buffer " *jieba-clone-timers*" nil)))
      (unwind-protect
          (with-current-buffer clone
            (should jieba-rs--boundaries-timer)
            (should jieba-rs--tags-timer)
            (should-not (eq boundary-timer jieba-rs--boundaries-timer))
            (should-not (eq tag-timer jieba-rs--tags-timer)))
        (kill-buffer clone))
      (should (memq boundary-timer timer-idle-list))
      (should (memq tag-timer timer-idle-list)))))

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

(ert-deftest jieba-rs-tests-persistence-rejects-unicode-whitespace ()
  "Reject file separators in words and tags under different syntax tables."
  (let ((jieba-rs-user-dict (make-temp-file "jieba-fields-")))
    (unwind-protect
        (progn
          (with-temp-file jieba-rs-user-dict (insert "原有词语 100 n\n"))
          (cl-letf (((symbol-function 'jieba-rs-module-add-word)
                     (lambda (&rest _) (ert-fail "Dictionary was modified"))))
            (dolist (mode '(fundamental-mode text-mode emacs-lisp-mode))
              (with-temp-buffer
                (funcall mode)
                (dolist (character '(0 9 10 11 12 13 32 #x85 #xa0 #x1680
                                       #x2000 #x2001 #x2002 #x2003 #x2004
                                       #x2005 #x2006 #x2007 #x2008 #x2009 #x200a
                                       #x2028 #x2029 #x202f #x205f #x3000))
                  (let ((field (concat "甲" (string character) "乙")))
                    (should-error (jieba-rs-add-word field 100 "n" t)
                                  :type 'user-error)
                    (should-error (jieba-rs-add-word "正常词语" 100 field t)
                                  :type 'user-error))))))
          (with-temp-buffer
            (insert-file-contents jieba-rs-user-dict)
            (should (equal (buffer-string) "原有词语 100 n\n"))))
      (delete-file jieba-rs-user-dict))))

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

(ert-deftest jieba-rs-tests-displays-share-tagged-lines ()
  "Share POS segmentation in either refresh order and retain raw motion."
  (dolist (order '((nil t) (t nil)))
    (with-temp-buffer
      (insert "杭研大厦中国北京")
      (let ((jieba-rs-hmm t)
            (segment (symbol-function 'jieba-rs-module-segment))
            (tag (symbol-function 'jieba-rs-module-segment-tag))
            (normalize (symbol-function 'jieba-rs--normalize-text))
            (segments 0) (tags 0) (normalizations 0))
        (cl-letf (((symbol-function 'jieba-rs-module-segment)
                   (lambda (&rest args)
                     (cl-incf segments)
                     (apply segment args)))
                  ((symbol-function 'jieba-rs-module-segment-tag)
                   (lambda (&rest args)
                     (cl-incf tags)
                     (apply tag args)))
                  ((symbol-function 'jieba-rs--normalize-text)
                   (lambda (&rest args)
                     (cl-incf normalizations)
                     (apply normalize args))))
          (dolist (tagged order) (jieba-rs--show-display tagged))
          (should (= tags 1))
          (should (= segments (if (car order) 0 1)))
          (should (= normalizations (+ tags segments)))
          (should (= (length jieba-rs-boundaries-overlays) 3))
          (should (= (length jieba-rs-tag-overlays) 4))
          (insert "中国")
          (setq segments 0 tags 0 normalizations 0)
          (dolist (tagged order) (jieba-rs--show-display tagged))
          (should (equal (list segments tags normalizations) '(0 1 1)))
          (should (equal (sort (mapcar #'overlay-start
                                       jieba-rs-boundaries-overlays) #'<)
                         (butlast (sort (mapcar #'overlay-start
                                                jieba-rs-tag-overlays) #'<))))
          ;; Motion still segments the original text, without POS overhead.
          (goto-char 1)
          (jieba-rs-forward-word)
          (should (= (point) 3))
          (should (equal (list segments tags normalizations) '(1 1 1)))
          (jieba-rs--clear-tags)
          (goto-char (point-max))
          (insert "北京")
          (setq segments 0 tags 0 normalizations 0)
          (jieba-rs--show-boundaries)
          (should (equal (list segments tags normalizations) '(1 0 1))))))))

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
  "Reject non-Unicode strings at every native boundary without panicking."
  (let ((version (jieba-rs-module-dictionary-version)))
    (dolist (invalid (list (unibyte-string #xff)
                           (encode-coding-string "中国北京" 'utf-8 t)))
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
                      :type 'wrong-type-argument)))
    (should (= version (jieba-rs-module-dictionary-version)))
    (should (equal (jieba-rs-module-segment "中国" nil) ["中国"]))))

(ert-deftest jieba-rs-tests-unibyte-motion-preserves-position ()
  "Reject encoded non-ASCII bytes before moving through a buffer."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert (encode-coding-string "中国北京" 'utf-8 t))
    (goto-char (point-min))
    (should-error (jieba-rs-forward-word) :type 'wrong-type-argument)
    (should (= (point) (point-min))))
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert "hello world")
    (goto-char (point-min))
    (jieba-rs-forward-word)
    (should (= (point) 6))
    (jieba-rs-forward-word)
    (should (= (point) (point-max)))))

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
    (setq-local jieba-rs-max-display-line-length nil)
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

(ert-deftest jieba-rs-tests-display-skips-long-lines ()
  "Skip whole long lines before native calls, including after editing."
  (with-temp-buffer
    (insert "中国\n" (make-string 20001 ?中) "\n北京")
    (let ((segment (symbol-function 'jieba-rs-module-segment))
          (tag (symbol-function 'jieba-rs-module-segment-tag))
          (calls 0))
      (cl-letf (((symbol-function 'jieba-rs-module-segment)
                 (lambda (text hmm)
                   (should (<= (length text) 3))
                   (cl-incf calls)
                   (funcall segment text hmm)))
                ((symbol-function 'jieba-rs-module-segment-tag)
                 (lambda (text hmm)
                   (should (<= (length text) 3))
                   (cl-incf calls)
                   (funcall tag text hmm))))
        (dotimes (_ 3)
          (goto-char 10000)
          (insert "甲")
          (dolist (tagged '(nil t))
            (let (words)
              (jieba-rs--map-visible-tokens
               (lambda (token) (push (aref token 2) words)) tagged)
              (should (equal (nreverse words)
                             (if tagged '("中国" "北京") '("中国")))))))
        (should (= calls 12))
        (cl-letf (((symbol-function 'jieba-rs--visible-range)
                   (lambda () '(10000 . 10020))))
          (dolist (tagged '(nil t))
            (jieba-rs--map-visible-tokens
             (lambda (_) (ert-fail "Long line was rendered")) tagged)))
        (should (= calls 12))))))

(ert-deftest jieba-rs-tests-display-line-limit-options ()
  "Honor exact line limits, unlimited display, narrowing and word motion."
  (dolist (case '((10 10 1) (10 11 0) (nil 11 1)))
    (with-temp-buffer
      (insert (make-string (nth 1 case) ?a) "\n")
      (let ((jieba-rs-max-display-line-length (car case))
            (tokens 0))
        (jieba-rs--map-visible-tokens (lambda (_) (cl-incf tokens)) t)
        (should (= tokens (nth 2 case))))))
  (with-temp-buffer
    (insert "中国北京")
    (let ((jieba-rs-max-display-line-length 2)
          (jieba-rs-hmm nil)
          words)
      (narrow-to-region 1 3)
      (jieba-rs--map-visible-tokens
       (lambda (token) (push (aref token 2) words)) t)
      (should (equal words '("中国")))
      (widen)
      (goto-char 1)
      (jieba-rs-forward-word 2)
      (should (= (point) (point-max))))))

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

(ert-deftest jieba-rs-tests-view-changes-schedule-refresh ()
  "Refresh after resizing and widening even when window start is fixed."
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (insert (apply #'concat (make-list 100 "中国\n")))
      (goto-char 1)
      (let ((window (selected-window))
            (end 22))
        (set-window-buffer (split-window-below) (other-buffer (current-buffer) t))
        (cl-letf (((symbol-function 'window-end)
                   (lambda (&rest _) end)))
          (jieba-rs-toggle-boundaries)
          (jieba-rs-toggle-tags)
          (should (= (length jieba-rs-tag-overlays) 7))
          (delete-other-windows)
          (setq end 64)
          ;; Batch mode needs explicit delivery of redisplay notifications.
          (run-hook-with-args 'window-size-change-functions window)
          (dolist (timer (list jieba-rs--boundaries-timer jieba-rs--tags-timer))
            (should (timerp timer))
            (apply (timer--function timer) (timer--args timer)))
          (should (= (length jieba-rs-tag-overlays) 21))
          (should (= (window-start window) 1))
          (dolist (narrow '(t nil))
            (if narrow (narrow-to-region 1 22) (widen))
            (let ((this-command (if narrow 'narrow-to-region 'widen)))
              (run-hooks 'post-command-hook))
            (dolist (timer (list jieba-rs--boundaries-timer jieba-rs--tags-timer))
              (should (timerp timer))
              (apply (timer--function timer) (timer--args timer)))
            (should (= (length jieba-rs-tag-overlays) (if narrow 7 21))))
          (let ((this-command 'forward-char))
            (run-hooks 'post-command-hook))
          (should-not jieba-rs--tags-timer)
          (jieba-rs--clear-display)
          (should-not (memq #'jieba-rs--window-change window-size-change-functions))
          (should-not jieba-rs--display-restriction))))))

(ert-deftest jieba-rs-tests-displays-observe-configuration ()
  "Refresh global and local options without disturbing local overrides."
  (let ((original-hmm (default-value 'jieba-rs-hmm))
        (first (generate-new-buffer " *jieba-config-first*"))
        (second (generate-new-buffer " *jieba-config-second*")))
    (unwind-protect
        (save-window-excursion
          (set-default 'jieba-rs-hmm nil)
          (delete-other-windows)
          (switch-to-buffer first)
          (set-window-buffer (split-window-right) second)
          (cl-letf (((symbol-function 'window-end)
                     (lambda (&rest _) (point-max))))
            (dolist (buffer (list first second))
              (with-current-buffer buffer
                (insert "杭研大厦\n中国北京\n")
                (goto-char 1)
                (jieba-rs-toggle-boundaries)
                (jieba-rs-toggle-tags)))
            (with-current-buffer second (setq-local jieba-rs-hmm nil))
            (cl-labels
                ((refresh ()
                   (dolist (timer (list jieba-rs--boundaries-timer
                                        jieba-rs--tags-timer))
                     (should (timerp timer))
                     (apply (timer--function timer) (timer--args timer))))
                 (positions ()
                   (sort (mapcar #'overlay-start jieba-rs-boundaries-overlays)
                         #'<)))
              ;; Customize runs outside either displayed source buffer.
              (with-temp-buffer (customize-set-variable 'jieba-rs-hmm t))
              (with-current-buffer first
                (should-not jieba-rs-boundaries-overlays)
                (refresh)
                (should (equal (positions) '(3 5 8)))
                (jieba-rs-forward-word)
                (should (= (point) 3)))
              (with-current-buffer second
                (should-not jieba-rs--boundaries-timer)
                (should (equal (positions) '(2 3 5 8)))
                ;; Plain buffer-local assignments are detected after commands.
                (setq-local jieba-rs-hmm t
                            jieba-rs-boundary-separator "|")
                (let ((this-command 'eval-expression))
                  (run-hooks 'post-command-hook))
                (refresh)
                (should (equal (positions) '(3 5 8)))
                (should (equal (overlay-get (car jieba-rs-boundaries-overlays)
                                            'after-string)
                               "|"))
                (dolist (option '((jieba-rs-max-display-line-length 1 nil)
                                  (jieba-rs-max-display-line-length nil t)
                                  (jieba-rs-normalize-rules ((t ("." . " "))) nil)))
                  (set (make-local-variable (car option)) (nth 1 option))
                  (let ((this-command 'eval-expression))
                    (run-hooks 'post-command-hook))
                  (refresh)
                  (should (eq (not (null jieba-rs-tag-overlays))
                              (nth 2 option))))
                (let ((this-command 'forward-char))
                  (run-hooks 'post-command-hook))
                (should-not jieba-rs--tags-timer)
                (jieba-rs--clear-display)
                (should-not jieba-rs--display-configuration)))))
      (kill-buffer first)
      (kill-buffer second)
      (set-default 'jieba-rs-hmm original-hmm))))

(ert-deftest jieba-rs-tests-display-failure-cleans-partial-overlays ()
  "Roll back first activation and allow an enabled display to recover."
  (save-window-excursion
    (dolist (tagged '(nil t))
      (with-temp-buffer
        (switch-to-buffer (current-buffer))
        (insert "中国北京\n" (string #x3fff80))
        (let ((toggle (if tagged #'jieba-rs-toggle-tags
                        #'jieba-rs-toggle-boundaries))
              (enabled (if tagged 'jieba-rs--tags-enabled
                         'jieba-rs--boundaries-enabled))
              (timer-var (if tagged 'jieba-rs--tags-timer
                           'jieba-rs--boundaries-timer))
              (hook (if tagged #'jieba-rs--tags-after-change
                      #'jieba-rs--boundaries-after-change)))
          (should-error (funcall toggle) :type 'wrong-type-argument)
          (should-not (symbol-value enabled))
          (should-not (overlays-in (point-min) (point-max)))
          (should-not (memq hook after-change-functions))
          (delete-region (1- (point-max)) (point-max))
          (funcall toggle)
          (should (symbol-value enabled))
          (should (overlays-in (point-min) (point-max)))
          (goto-char (point-max))
          (insert (string #x3fff80))
          (let ((timer (symbol-value timer-var)))
            (should-error (apply (timer--function timer) (timer--args timer))
                          :type 'wrong-type-argument))
          (should (symbol-value enabled))
          (should (memq hook after-change-functions))
          (should-not (overlays-in (point-min) (point-max)))
          (delete-region (1- (point-max)) (point-max))
          (let ((timer (symbol-value timer-var)))
            (should (timerp timer))
            (apply (timer--function timer) (timer--args timer)))
          (should (overlays-in (point-min) (point-max)))
          (should-not (symbol-value timer-var)))))))

(ert-deftest jieba-rs-tests-persistence-rejects-empty-tag ()
  "Reject an unrepresentable tag before changing memory or the file."
  (let ((jieba-rs-user-dict (make-temp-file "jieba-empty-tag-"))
        (version (jieba-rs-module-dictionary-version))
        (before (jieba-rs-module-segment-tag "中国" nil)))
    (unwind-protect
        (progn
          (with-temp-file jieba-rs-user-dict (insert "原词 100 n\n"))
          (should-error (jieba-rs-add-word "中国" 10000 "" t)
                        :type 'user-error)
          (should (= version (jieba-rs-module-dictionary-version)))
          (should (equal before (jieba-rs-module-segment-tag "中国" nil)))
          (should (equal (with-temp-buffer
                           (insert-file-contents jieba-rs-user-dict)
                           (buffer-string))
                         "原词 100 n\n")))
      (delete-file jieba-rs-user-dict))))

(ert-deftest jieba-rs-tests-refresh-reuses-trailing-whitespace-scan ()
  "Reuse the tail scan across refreshes and invalidate it when needed."
  (with-temp-buffer
    (insert "中国北京\n" (make-string 10000 ?\s))
    (should (= (jieba-rs--content-end) 5))
    (let ((cache jieba-rs--content-end-cache))
      (cl-letf (((symbol-function 'jieba-rs--visible-ranges)
                 (lambda () '((1 . 6)))))
        (dotimes (_ 3)
          (jieba-rs--map-visible-tokens #'ignore)
          (jieba-rs--map-visible-tokens #'ignore t))
        ;; Observe the cache itself: bytecode can inline the scan primitive.
        (should (eq cache jieba-rs--content-end-cache))
        (should (= (jieba-rs--content-end) 5))
        ;; An equal-size edit must invalidate the cached text position.
        (goto-char (point-max))
        (delete-char -1)
        (insert "新")
        (should (= (jieba-rs--content-end) (point-max)))
        (should-not (eq cache jieba-rs--content-end-cache))
        (narrow-to-region 1 4)
        (should (= (jieba-rs--content-end) 4))
        (widen)
        (should (= (jieba-rs--content-end) (point-max)))
        (jieba-rs--clear-display)
        (should-not jieba-rs--content-end-cache)))))

(ert-deftest jieba-rs-tests-extraction-commands-share-dispatch ()
  "Preserve method, count, HMM and accessible text in both commands."
  (with-temp-buffer
    (insert "前中国北京后")
    (narrow-to-region 2 6)
    (dolist (method '(tfidf textrank precise))
      (let ((jieba-rs-extract-function method)
            (jieba-rs-hmm nil)
            result)
        (cl-letf (((symbol-function 'jieba-rs-module-extract-keywords)
                   (lambda (&rest args) (cons 'keywords args)))
                  ((symbol-function 'jieba-rs-module-segment)
                   (lambda (&rest args) (cons 'precise args)))
                  ((symbol-function 'jieba-rs--display-extract-results)
                   (lambda (items _title) (setq result items))))
          (jieba-rs-extract-keywords-buffer 3)
          (should (equal result (if (eq method 'precise)
                                    '(precise "中国北京" nil)
                                  (list 'keywords "中国北京" 3 (symbol-name method)))))
          (jieba-rs-extract-keywords-region 2 4 5)
          (should (equal result (if (eq method 'precise)
                                    '(precise "中国" nil)
                                  (list 'keywords "中国" 5 (symbol-name method))))))))))

(provide 'jieba-rs-tests)
;;; jieba-rs-tests.el ends here
