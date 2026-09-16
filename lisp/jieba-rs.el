;;; jieba-rs.el --- Jieba Chinese segment -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Bingshan Chang <chang@bingshan.org>

;; Assisted-by: OpenCode:deepseek-v4-pro
;; Author: Bingshan Chang <chang@bingshan.org>
;; Keywords: chinese, segmentation
;; Package-Requires: ((emacs "30.1"))
;; Version: 0.1.0

;; This file is not part of GNU Emacs.

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation, either version 3 of the License,
;; or (at your option) any later version.

;; This file is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this file.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Jieba Chinese word segmentation for Emacs.
;;
;; Provides ~jieba-rs-mode~, a minor mode with commands to segment
;; Chinese text using the jieba-rs dynamic module.
;;
;; * Usage
;;
;; Toggle the mode in current buffer.
;;
;; #+begin_src emacs-lisp
;;   M-x jieba-rs-mode
;; #+end_src
;;
;; Segment the active region.
;;
;; #+begin_src emacs-lisp
;;   M-x jieba-rs-segment-region
;; #+end_src
;;
;; Segment the entire buffer.
;;
;; #+begin_src emacs-lisp
;;   M-x jieba-rs-segment-buffer
;; #+end_src
;;
;; Toggle word boundary display.
;;
;; #+begin_src emacs-lisp
;;   M-x jieba-rs-toggle-boundaries
;; #+end_src
;;
;; Toggle POS tag display.
;;
;; #+begin_src emacs-lisp
;;   M-x jieba-rs-toggle-tags
;; #+end_src
;;
;; Extract keywords by TextRank.
;;
;; #+begin_src emacs-lisp
;;   M-x jieba-rs-extract-keywords-region
;; #+end_src
;;
;; Extract keywords from the entire buffer.
;;
;; #+begin_src emacs-lisp
;;   M-x jieba-rs-extract-keywords-buffer
;; #+end_src
;;
;; * Customization
;;
;; ** ~jieba-rs-hmm~
;;
;; Enable HMM-based new word discovery.
;;
;; ** ~jieba-rs-segment-function~
;;
;; Choose the segmentation algorithm.
;;
;; ** ~jieba-rs-normalize-rules~
;;
;; Per-mode normalization rules for overlay positioning.
;;
;; ** ~jieba-rs-boundary-separator~
;;
;; String inserted between words as a boundary marker.
;;
;; ** ~jieba-rs-extract-function~
;;
;; Choose the extraction algorithm: tfidf (default), textrank,
;; or precise.
;;
;; ** ~jieba-rs-user-dict~
;;
;; Path to a user dictionary file, or nil to disable.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function jieba-rs-module-segment
                  "ext:jieba-rs-module" (text hmm))
(declare-function jieba-rs-module-segment-all
                  "ext:jieba-rs-module" (text))
(declare-function jieba-rs-module-segment-search
                  "ext:jieba-rs-module" (text hmm))
(declare-function jieba-rs-module-segment-tag
                  "ext:jieba-rs-module" (text hmm))
(declare-function jieba-rs-module-load-user-dict
                  "ext:jieba-rs-module" (path))
(declare-function jieba-rs-module-add-word
                  "ext:jieba-rs-module" (word freq tag))
(declare-function jieba-rs-module-extract-keywords
                  "ext:jieba-rs-module" (text top_k method))

(declare-function jieba-rs-module-dictionary-version
                  "ext:jieba-rs-module" ())

(defgroup jieba-rs nil
  "Jieba Chinese word segmentation."
  :prefix "jieba-rs-"
  :group 'tools)

(defcustom jieba-rs-hmm t
  "When non-nil, enable HMM-based new word discovery."
  :type 'boolean
  :group 'jieba-rs)

(defcustom jieba-rs-user-dict
  (expand-file-name "jieba-rs/user.dict" user-emacs-directory)
  "Path to a user dictionary file, or nil to disable."
  :type '(choice (const :tag "None" nil)
                 (file :tag "Dictionary file"))
  :group 'jieba-rs)

(defcustom jieba-rs-segment-function 'jieba-rs-module-segment
  "Segmentation function to use.
`jieba-rs-module-segment' uses precise mode (default).
`jieba-rs-module-segment-all' uses full mode,
scanning all possible cuts.
`jieba-rs-module-segment-search' uses search engine mode."
  :type '(choice (const :tag "Precise" jieba-rs-module-segment)
                 (const :tag "Full" jieba-rs-module-segment-all)
                 (const :tag "Search" jieba-rs-module-segment-search))
  :group 'jieba-rs)

(defcustom jieba-rs-normalize-rules
  '((t ("[\u0000-\u001f\u007f-\u009f\ufeff]"
        . " ")
       ("[\t\n\r\f　]"
        . " ")))
  "Normalization rules for text before overlay segmentation.
Each replacement must be exactly one space so that the
normalized text keeps the same length as the buffer text.
Each element is (MODE . RULES) where MODE is a major-mode symbol
or t for the default fallback.  RULES is a list of (REGEXP
. REPLACEMENT) pairs applied in order with \
`replace-regexp-in-string'."
  :type '(repeat
          (cons (choice (const t)
                        (symbol :tag "Major mode"))
                (repeat (cons (regexp :tag "Pattern")
                              (string :tag "Replacement")))))
  :group 'jieba-rs)

(defcustom jieba-rs-extract-function 'tfidf
  "Extraction function to use with keyword extraction commands.
`tfidf' uses TF-IDF keyword extraction.
`textrank' uses TextRank keyword extraction.
`precise' uses precise word segmentation."
  :type '(choice (const :tag "TF-IDF" tfidf)
                 (const :tag "TextRank" textrank)
                 (const :tag "Precise segmentation" precise))
  :group 'jieba-rs)

(defcustom jieba-rs-boundary-separator "  "
  "String inserted between words as a boundary marker."
  :type 'string
  :group 'jieba-rs)

(defface jieba-rs-boundary-face
  '((t :inherit shadow))
  "Face for word boundary separators."
  :group 'jieba-rs)

(defface jieba-rs-tag-face
  '((t :inherit font-lock-keyword-face :slant italic))
  "Face for POS tag annotations."
  :group 'jieba-rs)

(defconst jieba-rs-tag-names
  '(("n" . "noun") ("nr" . "propn") ("ns" . "propn")
    ("nt" . "propn") ("nz" . "propn") ("v" . "verb")
    ("vd" . "verb") ("vn" . "verb") ("a" . "adj")
    ("ad" . "adj") ("an" . "adj") ("d" . "adv")
    ("r" . "pron") ("p" . "adp") ("c" . "cconj")
    ("u" . "part") ("m" . "num") ("q" . "num")
    ("f" . "noun") ("t" . "noun") ("s" . "noun")
    ("z" . "adj") ("w" . "punct") ("x" . "sym")
    ("b" . "noun") ("e" . "intj") ("y" . "part")
    ("o" . "intj") ("h" . "noun") ("k" . "noun")
    ("i" . "noun") ("l" . "noun") ("j" . "noun"))
  "Alist mapping ICTCLAS POS codes to Universal Dependencies tags.")

(defvar-local jieba-rs--segment-cache nil
  "Cached line bounds and segmentation results.")

(defvar-local jieba-rs--segment-cache-context nil
  "Buffer, configuration and dictionary state of cached results.")

(defvar-local jieba-rs--boundaries-enabled nil
  "Whether boundary display is enabled in this buffer.")

(defvar-local jieba-rs--tags-enabled nil
  "Whether part-of-speech display is enabled in this buffer.")

(defvar-local jieba-rs-boundaries-overlays nil
  "List of word boundary overlays in the current buffer.")

(defvar-local jieba-rs--boundaries-timer nil
  "Pending idle timer for boundary refresh.")

(defvar-local jieba-rs-tag-overlays nil
  "List of POS tag overlays in the current buffer.")

(defvar-local jieba-rs--tags-timer nil
  "Pending idle timer for tag refresh.")

(defun jieba-rs--load-module ()
  "Load the native module if not already loaded."
  (unless (featurep 'jieba-rs-module)
    (let ((suffixes (list module-file-suffix)))
      (module-load
       (or (locate-file "jieba-rs-module" load-path suffixes)
           (when load-file-name
             (expand-file-name
              (concat "jieba-rs-module" module-file-suffix)
              (file-name-directory load-file-name)))
           (error "Cannot find jieba-rs-module%s"
                  module-file-suffix))))))

(defun jieba-rs--load-user-dict ()
  "Load the user dictionary if `jieba-rs-user-dict' is set."
  (when (and jieba-rs-user-dict
             (file-exists-p jieba-rs-user-dict))
    (condition-case err
        (jieba-rs-module-load-user-dict
         (expand-file-name jieba-rs-user-dict))
      (error
       (display-warning 'jieba-rs
                        (format "Failed to load user dict: %s"
                                (error-message-string err))
                        :warning)))))

(defun jieba-rs--normalize-text (beg end)
  "Normalize text in region BEG..END for overlay segmentation.
Respects `jieba-rs-normalize-rules' for the current major mode."
  (let ((text (buffer-substring-no-properties beg end))
        (rules (cdr (or (cl-find-if
                         (lambda (entry)
                           (and (not (eq (car entry) t))
                                (derived-mode-p (car entry))))
                         jieba-rs-normalize-rules)
                        (assq t jieba-rs-normalize-rules)))))
    (dolist (rule rules)
      (setq text (replace-regexp-in-string
                  (car rule) (cdr rule) text)))
    text))

(defun jieba-rs--segment-function-arity (fn)
  "Return the number of arguments FN expects.
`jieba-rs-module-segment-all' takes 1 argument (text only);
others take 2 (text hmm)."
  (if (eq fn 'jieba-rs-module-segment-all) 1 2))

(defun jieba-rs--call-segment (text)
  "Segment TEXT using `jieba-rs-segment-function'."
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (let* ((fn jieba-rs-segment-function)
         (arity (jieba-rs--segment-function-arity fn)))
    (if (= arity 1)
        (funcall fn text)
      (funcall fn text jieba-rs-hmm))))

(defun jieba-rs--format-words (words)
  "Return WORDS as a single string with | separators."
  (mapconcat #'identity words " | "))

(defun jieba-rs--show-buffer (words title)
  "Display WORDS in *jieba-rs-segment* buffer.
TITLE is shown as a header line followed by a separator."
  (let ((buf (get-buffer-create "*jieba-rs-segment*"))
        (text (jieba-rs--format-words words)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (special-mode)
        (insert title "\n"
                (make-string (string-width title) ?─) "\n\n")
        (insert text "\n")
        (goto-char (point-min))))
    (display-buffer buf)))

(defun jieba-rs--show-tooltip (text)
  "Show TEXT via `tooltip-show' when `tooltip-mode' is on.
In text terminals this falls back to the echo area."
  (if (and (bound-and-true-p tooltip-mode)
           (fboundp 'tooltip-show))
      (tooltip-show text)
    (message "%s" text)))

(defun jieba-rs--display-extract-results (items title)
  "Display ITEMS in *jieba-rs-extract* buffer with TITLE."
  (let ((buf (get-buffer-create "*jieba-rs-extract*"))
        (formatter (if (eq jieba-rs-extract-function
                           'precise)
                       (lambda (item) item)
                     (lambda (item)
                       (format "%s  %s"
                               (plist-get item :keyword)
                               (plist-get item :weight))))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (special-mode)
        (insert title "\n"
                (make-string (string-width title)
                             ?─) "\n\n")
        (dolist (item (append items nil))
          (insert (funcall formatter item) "\n"))
        (goto-char (point-min))))
    (display-buffer buf)))

(defun jieba-rs--line-tokens (position &optional tagged normalized)
  "Return cached line bounds and tokens around POSITION.
TAGGED requests POS categories; NORMALIZED applies overlay rules.
Each token is a vector of start, end, word and optional category."
  (let ((context (list (buffer-chars-modified-tick)
                       (point-min) (point-max) jieba-rs-hmm major-mode
                       jieba-rs-normalize-rules
                       (jieba-rs-module-dictionary-version))))
    (unless (equal context jieba-rs--segment-cache-context)
      (setq jieba-rs--segment-cache-context (copy-tree context)
            jieba-rs--segment-cache (make-hash-table :test #'equal))))
  (save-excursion
    (goto-char position)
    (let* ((beg (line-beginning-position))
           (end (min (point-max) (1+ (line-end-position))))
           (key (list beg end tagged normalized)))
      (or (gethash key jieba-rs--segment-cache)
          (let* ((text (if normalized (jieba-rs--normalize-text beg end)
                         (buffer-substring-no-properties beg end)))
                 (items (if tagged
                            (jieba-rs-module-segment-tag text jieba-rs-hmm)
                          (jieba-rs-module-segment text jieba-rs-hmm)))
                 (tokens (make-vector (length items) nil))
                 (pos beg))
            (dotimes (i (length items))
              (let* ((item (aref items i))
                     (word (if tagged (plist-get item :word) item))
                     (next (+ pos (length word))))
                (aset tokens i
                      (vector pos next word
                              (when tagged (plist-get item :category))))
                (setq pos next)))
            ;; Bound retained data when navigating many different lines.
            (when (>= (hash-table-count jieba-rs--segment-cache) 128)
              (clrhash jieba-rs--segment-cache))
            (puthash key (vector beg end tokens)
                     jieba-rs--segment-cache))))))

(defun jieba-rs--visible-range ()
  "Return the visible range, or the accessible range if undisplayed."
  (let* ((window (get-buffer-window nil t))
         (beg (if window (window-start window) (point-min)))
         (end (if window (window-end window t) (point-max))))
    (if (and end (> end beg))
        (cons (max beg (point-min)) (min end (point-max)))
      (cons (point-min) (point-max)))))

(defun jieba-rs--map-visible-tokens (function &optional tagged)
  "Call FUNCTION for visible normalized tokens, optionally TAGGED."
  (let* ((range (jieba-rs--visible-range))
         (beg (car range))
         (end (cdr range))
         (content-end (save-excursion
                        (goto-char (point-max))
                        (skip-chars-backward " \t\n\r\f　")
                        (point))))
    (save-excursion
      (goto-char beg)
      (while (< (point) end)
        (let* ((line (jieba-rs--line-tokens (point) tagged t))
               (tokens (aref line 2)))
          (cl-loop for token across tokens
                   for pos = (aref token 1)
                   when (and (not (string-blank-p (aref token 2)))
                             (>= pos beg)
                             (if tagged
                                 (and (<= pos end) (<= pos content-end))
                               (and (< pos end) (< pos content-end))))
                   do (funcall function token))
          (goto-char (aref line 1)))))))

(defun jieba-rs--token-index (tokens position backward)
  "Find the token in TOKENS reachable from POSITION moving BACKWARD."
  (let ((low 0)
        (high (length tokens)))
    (while (< low high)
      (let* ((mid (/ (+ low high) 2))
             (token (aref tokens mid)))
        (if (if backward (< (aref token 0) position)
              (<= (aref token 1) position))
            (setq low (1+ mid))
          (setq high mid))))
    (if backward (1- low) low)))

(defun jieba-rs--move-word (count)
  "Move COUNT words using cached boundaries of complete lines."
  (let ((backward (< count 0))
        (remaining (abs count)))
    (while (and (> remaining 0)
                (if backward (> (point) (point-min))
                  (< (point) (point-max))))
      (let* ((position (if (and backward (bolp)) (1- (point)) (point)))
             (line (jieba-rs--line-tokens position))
             (tokens (aref line 2))
             (index (jieba-rs--token-index tokens (point) backward)))
        (while (and (> remaining 0) (>= index 0) (< index (length tokens)))
          (let ((token (aref tokens index)))
            (unless (string-blank-p (aref token 2))
              (goto-char (aref token (if backward 0 1)))
              (setq remaining (1- remaining))))
          (setq index (+ index (if backward -1 1))))
        (when (> remaining 0)
          (goto-char (aref line (if backward 0 1))))))))

(defun jieba-rs--update-display-hooks ()
  "Keep refresh and cleanup hooks consistent with display state."
  (dolist (entry
           '((jieba-rs--boundaries-enabled after-change-functions
                                           jieba-rs--boundaries-after-change)
             (jieba-rs--boundaries-enabled window-scroll-functions
                                           jieba-rs--boundaries-window-scroll)
             (jieba-rs--tags-enabled after-change-functions
                                     jieba-rs--tags-after-change)
             (jieba-rs--tags-enabled window-scroll-functions
                                     jieba-rs--tags-window-scroll)))
    (if (symbol-value (car entry))
        (add-hook (nth 1 entry) (nth 2 entry) nil t)
      (remove-hook (nth 1 entry) (nth 2 entry) t)))
  (dolist (entry
           '((post-command-hook . jieba-rs--post-command-scroll-check)
             (window-buffer-change-functions . jieba-rs--window-buffer-change)
             (change-major-mode-hook . jieba-rs--clear-display)
             (kill-buffer-hook . jieba-rs--clear-display)))
    (if (or jieba-rs--boundaries-enabled jieba-rs--tags-enabled)
        (add-hook (car entry) (cdr entry) nil t)
      (remove-hook (car entry) (cdr entry) t))))

(defun jieba-rs--clear-display ()
  "Disable both displays and cancel their pending refreshes."
  (jieba-rs--clear-boundaries)
  (jieba-rs--clear-tags)
  (setq jieba-rs--segment-cache nil
        jieba-rs--segment-cache-context nil))

(defun jieba-rs--window-buffer-change (window)
  "Refresh enabled displays when WINDOW starts showing this buffer."
  (with-current-buffer (window-buffer window)
    (when jieba-rs--boundaries-enabled
      (jieba-rs--schedule-refresh 'boundaries window))
    (when jieba-rs--tags-enabled
      (jieba-rs--schedule-refresh 'tags window))))

(defun jieba-rs--run-refresh (buffer window function timer-variable)
  "Refresh BUFFER in WINDOW using FUNCTION and clear TIMER-VARIABLE."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (set timer-variable nil)
      (let ((target (if (and (window-live-p window)
                             (eq (window-buffer window) buffer))
                        window
                      (get-buffer-window buffer t))))
        (when (and target
                   (if (eq timer-variable 'jieba-rs--boundaries-timer)
                       jieba-rs--boundaries-enabled
                     jieba-rs--tags-enabled))
          (with-selected-window target
            (funcall function)))))))

(defun jieba-rs--schedule-refresh (kind &optional window delay)
  "Schedule a refresh of KIND in WINDOW after idle DELAY seconds."
  (let* ((boundaries (eq kind 'boundaries))
         (timer-variable (if boundaries 'jieba-rs--boundaries-timer
                           'jieba-rs--tags-timer))
         (function (if boundaries #'jieba-rs--refresh-boundaries
                     #'jieba-rs--refresh-tags)))
    (when (symbol-value timer-variable)
      (cancel-timer (symbol-value timer-variable)))
    (set timer-variable
         (run-with-idle-timer
          (or delay 0) nil #'jieba-rs--run-refresh
          (current-buffer) (or window (get-buffer-window nil t))
          function timer-variable))))

(defun jieba-rs--clear-boundaries ()
  "Disable boundaries display and cancel scheduled refresh."
  (mapc #'delete-overlay jieba-rs-boundaries-overlays)
  (when jieba-rs--boundaries-timer
    (cancel-timer jieba-rs--boundaries-timer))
  (setq jieba-rs-boundaries-overlays nil
        jieba-rs--boundaries-timer nil
        jieba-rs--boundaries-enabled nil)
  (jieba-rs--update-display-hooks))

(defun jieba-rs--boundaries-after-change (&rest _)
  "Clear boundaries and schedule a visible-window refresh."
  (mapc #'delete-overlay jieba-rs-boundaries-overlays)
  (setq jieba-rs-boundaries-overlays nil)
  (jieba-rs--schedule-refresh
   'boundaries nil (if (> (buffer-size) 10000) 0.15 0)))

(defun jieba-rs--boundaries-window-scroll (window _new-start)
  "Schedule a boundaries refresh when WINDOW scrolls."
  (when jieba-rs--boundaries-enabled
    (jieba-rs--schedule-refresh 'boundaries window)))

(defun jieba-rs--refresh-boundaries ()
  "Rebuild boundary overlays for the visible window."
  (when jieba-rs--boundaries-timer
    (cancel-timer jieba-rs--boundaries-timer))
  (setq jieba-rs--boundaries-timer nil)
  (mapc #'delete-overlay jieba-rs-boundaries-overlays)
  (setq jieba-rs-boundaries-overlays nil)
  (jieba-rs--show-boundaries))

(defun jieba-rs--show-boundaries ()
  "Show word boundaries in the current buffer."
  (setq jieba-rs--boundaries-enabled t)
  (jieba-rs--map-visible-tokens
   (lambda (token)
     (let* ((pos (aref token 1))
            (ov (make-overlay pos pos)))
       (overlay-put ov 'priority 0)
       (overlay-put ov 'after-string
                    (propertize jieba-rs-boundary-separator
                                'face 'jieba-rs-boundary-face))
       (push ov jieba-rs-boundaries-overlays))))
  (jieba-rs--update-display-hooks))

(defun jieba-rs--clear-tags ()
  "Disable tags display and cancel scheduled refresh."
  (mapc #'delete-overlay jieba-rs-tag-overlays)
  (when jieba-rs--tags-timer
    (cancel-timer jieba-rs--tags-timer))
  (setq jieba-rs-tag-overlays nil
        jieba-rs--tags-timer nil
        jieba-rs--tags-enabled nil)
  (jieba-rs--update-display-hooks))

(defun jieba-rs--tags-after-change (&rest _)
  "Clear tags and schedule a visible-window refresh."
  (mapc #'delete-overlay jieba-rs-tag-overlays)
  (setq jieba-rs-tag-overlays nil)
  (jieba-rs--schedule-refresh
   'tags nil (if (> (buffer-size) 10000) 0.15 0)))

(defun jieba-rs--refresh-tags ()
  "Rebuild tag overlays for the visible window."
  (when jieba-rs--tags-timer
    (cancel-timer jieba-rs--tags-timer))
  (setq jieba-rs--tags-timer nil)
  (mapc #'delete-overlay jieba-rs-tag-overlays)
  (setq jieba-rs-tag-overlays nil)
  (jieba-rs--show-tags))

(defun jieba-rs--tags-window-scroll (window _new-start)
  "Schedule a tags refresh when WINDOW scrolls."
  (when jieba-rs--tags-enabled
    (jieba-rs--schedule-refresh 'tags window)))

(defun jieba-rs--show-tags ()
  "Show POS tags in the current buffer."
  (setq jieba-rs--tags-enabled t)
  (jieba-rs--map-visible-tokens
   (lambda (token)
     (let* ((pos (aref token 1))
            (cat (aref token 3))
            (label (or (cdr (assoc cat jieba-rs-tag-names)) cat))
            (ov (make-overlay pos pos)))
       (overlay-put ov 'priority 1)
       (overlay-put ov 'after-string
                    (propertize label 'display '(raise -0.3)
                                'face 'jieba-rs-tag-face))
       (push ov jieba-rs-tag-overlays)))
   t)
  (jieba-rs--update-display-hooks))

(defun jieba-rs--post-command-scroll-check ()
  "Schedule refreshes after commands that change the view."
  (when (memq this-command
              '(recenter recenter-top-bottom
                         beginning-of-buffer end-of-buffer))
    (when jieba-rs--boundaries-enabled
      (jieba-rs--schedule-refresh 'boundaries))
    (when jieba-rs--tags-enabled
      (jieba-rs--schedule-refresh 'tags))))

(defun jieba-rs--append-word (file word freq tag)
  "Append WORD with FREQ and TAG as a separate record in FILE."
  (with-temp-buffer
    (let ((size (when (file-exists-p file)
                  (file-attribute-size (file-attributes file)))))
      (when (and size (> size 0))
        (insert-file-contents-literally file nil (1- size) size))
      (let ((needs-newline (and (> (buffer-size) 0)
                                (not (eq (char-before (point-max)) ?\n)))))
        (erase-buffer)
        (when needs-newline (insert "\n"))))
    (insert (format "%s %d%s\n" word freq
                    (if tag (concat " " tag) "")))
    (let ((coding-system-for-write 'utf-8-unix))
      (write-region nil nil file 'append 'quiet))))

(defun jieba-rs-add-word (word &optional freq tag persist)
  "Add WORD to the Jieba dictionary.
FREQ is the word frequency; nil triggers auto-suggestion.
TAG is an optional POS tag.
With prefix arg PERSIST, append the entry to the user dict file.
If writing the file fails, WORD remains available for this session."
  (interactive
   (list (read-string "Word: ")
         nil nil current-prefix-arg))
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (let ((file (when persist
                (unless jieba-rs-user-dict
                  (user-error "Cannot persist: jieba-rs-user-dict is nil"))
                (unless (and (stringp word) (not (string-empty-p word))
                             (not (string-match-p "[[:space:]\0]" word))
                             (or (null tag)
                                 (and (stringp tag)
                                      (not (string-match-p "[[:space:]\0]" tag)))))
                  (user-error "Dictionary words and tags must be single fields"))
                (expand-file-name jieba-rs-user-dict))))
    (when file
      (make-directory (file-name-directory file) t))
    (let ((f (jieba-rs-module-add-word word freq tag)))
      (when file
        (jieba-rs--append-word file word f tag))
      f)))

(defun jieba-rs-forward-word (&optional arg)
  "Move point forward ARG Chinese words."
  (interactive "^p")
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (jieba-rs--move-word (or arg 1)))

(defun jieba-rs-backward-word (&optional arg)
  "Move point backward ARG Chinese words."
  (interactive "^p")
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (jieba-rs--move-word (- (or arg 1))))

(defun jieba-rs-forward-sentence (&optional arg)
  "Move point forward ARG Chinese sentences.
An unterminated final sentence ends at the accessible buffer end."
  (interactive "^p")
  (let ((n (or arg 1)))
    (if (< n 0)
        (jieba-rs-backward-sentence (- n))
      (dotimes (_ n)
        (skip-chars-forward " \t\n\r\f　")
        (unless (re-search-forward "[。！？\n]+" nil t)
          (goto-char (point-max)))))))

(defun jieba-rs-backward-sentence (&optional arg)
  "Move point backward ARG Chinese sentences.
Stop at the sentence start, skipping its trailing punctuation."
  (interactive "^p")
  (let ((n (or arg 1)))
    (if (< n 0)
        (jieba-rs-forward-sentence (- n))
      (dotimes (_ n)
        (skip-chars-backward "。！？ \t\n\r\f　")
        (if (re-search-backward "[。！？\n]+" nil t)
            (goto-char (match-end 0))
          (goto-char (point-min)))
        (skip-chars-forward " \t\r\f　")))))

;;;###autoload
(defun jieba-rs-toggle-boundaries ()
  "Toggle display of word segmentation boundaries."
  (interactive)
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (if jieba-rs--boundaries-enabled
      (jieba-rs--clear-boundaries)
    (jieba-rs--show-boundaries)))

;;;###autoload
(defun jieba-rs-toggle-tags ()
  "Toggle display of part-of-speech tags."
  (interactive)
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (if jieba-rs--tags-enabled
      (jieba-rs--clear-tags)
    (jieba-rs--show-tags)))

;;;###autoload
(defun jieba-rs-segment-region (start end)
  "Segment the region from START to END.
Display results in a buffer and show a tooltip at START
when `tooltip-mode' is enabled."
  (interactive "r")
  (let* ((text (buffer-substring-no-properties start end))
         (words (jieba-rs--call-segment text))
         (title (format "Region %d..%d — %s"
                        start end
                        jieba-rs-segment-function)))
    (jieba-rs--show-buffer words title)
    (save-excursion
      (goto-char start)
      (jieba-rs--show-tooltip (jieba-rs--format-words words)))))

;;;###autoload
(defun jieba-rs-segment-buffer ()
  "Segment the entire buffer (respecting narrowing).
Display results in a buffer."
  (interactive)
  (let* ((text (buffer-substring-no-properties
                (point-min) (point-max)))
         (words (jieba-rs--call-segment text))
         (title (format "Buffer %s — %s"
                        (buffer-name)
                        jieba-rs-segment-function)))
    (jieba-rs--show-buffer words title)))

;;;###autoload
(defun jieba-rs-extract-keywords-region (start end &optional top-k)
  "Extract TOP-K keywords from region START..END.
In `textrank' mode, uses TextRank keyword extraction.
In `precise' mode, uses word segmentation."
  (interactive "r\nP")
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (let* ((k (if (numberp top-k) top-k
              (read-number "Top K: " 10)))
         (text (buffer-substring-no-properties start end))
         (items (cond ((eq jieba-rs-extract-function 'textrank)
                       (jieba-rs-module-extract-keywords
                        text k "textrank"))
                      ((eq jieba-rs-extract-function 'tfidf)
                       (jieba-rs-module-extract-keywords
                        text k "tfidf"))
                      (t
                       (jieba-rs-module-segment
                        text jieba-rs-hmm))))
         (title (format "Region %d..%d — %s" start end
                        jieba-rs-extract-function)))
    (jieba-rs--display-extract-results items title)))

;;;###autoload
(defun jieba-rs-extract-keywords-buffer (&optional top-k)
  "Extract TOP-K keywords from the entire buffer."
  (interactive "P")
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (let* ((k (if (numberp top-k) top-k
              (read-number "Top K: " 10)))
         (text (buffer-substring-no-properties
                (point-min) (point-max)))
         (items (cond ((eq jieba-rs-extract-function 'textrank)
                       (jieba-rs-module-extract-keywords
                        text k "textrank"))
                      ((eq jieba-rs-extract-function 'tfidf)
                       (jieba-rs-module-extract-keywords
                        text k "tfidf"))
                      (t
                       (jieba-rs-module-segment
                        text jieba-rs-hmm))))
         (title (format "Buffer %s — %s" (buffer-name)
                        jieba-rs-extract-function)))
    (jieba-rs--display-extract-results items title)))

(defvar jieba-rs-mode-map
  (let ((map (make-sparse-keymap)))
    (keymap-set map "<remap> <forward-word>"
                #'jieba-rs-forward-word)
    (keymap-set map "<remap> <backward-word>"
                #'jieba-rs-backward-word)
    (keymap-set map "<remap> <forward-sentence>"
                #'jieba-rs-forward-sentence)
    (keymap-set map "<remap> <backward-sentence>"
                #'jieba-rs-backward-sentence)
    map)
  "Keymap for `jieba-rs-mode'.")

;;;###autoload
(define-minor-mode jieba-rs-mode
  "Toggle Jieba Chinese word segmentation mode.

When enabled, provides commands to segment Chinese text using
the jieba-rs dynamic module.  Use `jieba-rs-segment-function'
to choose the segmentation algorithm.

\\{jieba-rs-mode-map}"
  :lighter " Jieba"
  :keymap jieba-rs-mode-map
  :group 'jieba-rs
  (if (not jieba-rs-mode)
      (jieba-rs--clear-display)
    (condition-case err
        (progn
          (jieba-rs--load-module)
          (jieba-rs--load-user-dict))
      (error
       (display-warning 'jieba-rs
                        (format "Failed to load module: %s"
                                (error-message-string err))
                        :error)
       (jieba-rs-mode -1)))))

(provide 'jieba-rs)
;;; jieba-rs.el ends here
