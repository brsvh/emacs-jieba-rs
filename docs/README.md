```
Copyright (C) 2026 Bingshan Chang <chang@bingshan.org>
Permission is granted to copy, distribute and/or modify this document
under the terms of the GNU Free Documentation License, Version 1.3
or any later version published by the Free Software Foundation;
with no Invariant Sections, no Front-Cover Texts, and no Back-Cover Texts.
A copy of the license is included in the section entitled "GNU
Free Documentation License".
```

# emacs-jieba-rs

为 GNU Emacs 提供中文分词、词句移动、词性标注、关键词提取和可视词边界。Emacs 包名为 `jieba-rs`，通过 Rust 动态模块调用上游
[`jieba-rs`](https://github.com/messense/jieba-rs)。

## 安装与启用

### 要求

- GNU Emacs 30.1 或更高版本，启用动态模块支持。当前 CI 使用 Emacs 31。
- 从源码构建需要 Rust 1.88 或更高版本、Cargo、C 编译器和 GNU Make。

Makefile 使用 Linux 模块后缀 `.so`，flake 的预定义输出仅支持 `x86_64-linux`。其他平台需要自行调整构建配置。

### 从源码安装

```sh
git clone https://codeberg.org/bingshan/emacs-jieba-rs.git
cd emacs-jieba-rs
make local
```

`make local` 构建 release 模块并将其放入 `lisp/`，同时生成包描述和自动加载文件。在 Emacs 配置中加入：

```elisp
(add-to-list 'load-path "/path/to/emacs-jieba-rs/lisp")
(require 'jieba-rs)
```

使用 Nix 安装的方法见 [Nix](#nix)。

### 启用

执行 `M-x jieba-rs-mode`，在当前缓冲区启用并加载原生模块。若需自动启用，可在相应主模式的 hook 中调用
`(jieba-rs-mode 1)`。

启用后，使用 `M-f`、`M-b` 按中文词移动，`M-e`、`M-a` 按中文句移动。其他操作通过 `M-x` 调用：

| 命令 | 用途 |
| -- | -- |
| `jieba-rs-segment-region` | 对选中区域分词 |
| `jieba-rs-segment-buffer` | 对缓冲区分词 |
| `jieba-rs-extract-keywords-region` | 提取选中区域的关键词 |
| `jieba-rs-extract-keywords-buffer` | 提取缓冲区的关键词 |
| `jieba-rs-toggle-boundaries` | 切换可视词边界 |
| `jieba-rs-toggle-tags` | 切换词性标签 |
| `jieba-rs-add-word` | 添加词语；加 `C-u` 同时保存到用户词典 |

缓冲区分词和关键词提取都遵守窄化范围。所有选项和外观可通过 `M-x customize-group RET jieba-rs RET` 设置。

## 功能与配置

### 分词

区域和缓冲区分词命令将结果显示在结果缓冲区中，由 `jieba-rs-segment-function` 选择算法：

| 模式 | 函数 | 说明 |
| -- | -- | -- |
| 精确模式（默认） | `jieba-rs-module-segment` | 尽可能准确地切分文本 |
| 全模式 | `jieba-rs-module-segment-all` | 扫描所有可能的词语 |
| 搜索引擎模式 | `jieba-rs-module-segment-search` | 生成用于搜索索引的细粒度切分 |

`jieba-rs-hmm` 默认为 `t`，控制精确模式和搜索引擎模式的新词发现；全模式不使用 HMM。词移动和可视词边界固定使用精确模式，不受
`jieba-rs-segment-function` 影响。

### 词句移动

`jieba-rs-mode` 重映射标准移动命令，因此自定义的原命令键位也会沿用：

| 标准命令 | 替代命令 | 默认键位 |
| -- | -- | -- |
| `forward-word` | `jieba-rs-forward-word` | `M-f` |
| `backward-word` | `jieba-rs-backward-word` | `M-b` |
| `forward-sentence` | `jieba-rs-forward-sentence` | `M-e` |
| `backward-sentence` | `jieba-rs-backward-sentence` | `M-a` |

词移动遵守 `jieba-rs-hmm`。句移动以 `。`、`！`、`？` 和换行为分隔符。

### 词边界与词性标签

两种显示都使用覆盖层，不改写文本。覆盖层只覆盖当前窗口的可见范围，并随编辑和滚动刷新。

- `jieba-rs-boundary-separator` 设置词间分隔符，默认为两个空格。
- `jieba-rs-boundary-face` 设置词边界外观，默认继承 `shadow`。
- `jieba-rs-tag-face` 设置词性标签外观，默认继承 `font-lock-keyword-face` 并使用斜体。

常见词性代码会显示为 `noun`、`verb`、`adj` 等类别；未映射的代码原样显示。 `jieba-rs-normalize-rules`
只处理覆盖层分词用的文本副本，默认将控制字符和部分空白替换为空格。自定义规则应逐字符匹配，并替换为一个普通空格，以保持覆盖层位置与原文一致。

### 关键词提取

`jieba-rs-extract-function` 可设为 `tfidf`（默认）或 `textrank`。命令会询问关键词数量 Top K，默认
10；也可用数值前缀直接指定，例如 `C-u 5 M-x jieba-rs-extract-keywords-region`。

设为 `precise` 则返回精确模式的分词结果，不按 Top K 限制数量。

### 用户词典

`jieba-rs-user-dict` 默认为 Emacs 用户目录下的 `jieba-rs/user.dict`。
启用次要模式时会加载该文件（如果存在）。每行包含词语、词频和可选词性，以空格分隔，例如 `星际争霸 100 nz` 或 `量子计算机 200`。

`M-x jieba-rs-add-word` 将词语加入当前会话；`C-u M-x jieba-rs-add-word` 还会追加到该文件。将
`jieba-rs-user-dict` 设为 `nil` 会禁用自动加载和保存。

词典由同一 Emacs 进程的所有缓冲区共享。禁用次要模式或将路径设为 `nil`，不会撤销已经加载或添加的词语。

## Nix

### 试用与构建

在仓库根目录执行 `nix run .#emacs31-with-jieba-rs`，可用独立初始化目录启动带有本包的 Emacs 31。启动后执行
`M-x jieba-rs-mode` 即可使用。其他包输出为：

| 输出 | 用途 |
| -- | -- |
| `jieba-rs` | 包含 Rust 模块的 Emacs 包 |
| `jieba-rs-module` | Rust 动态模块；构建时运行 Cargo 测试 |

例如，`nix build .#jieba-rs` 构建 Emacs 包。测试命令见下文。

### 集成到 NixOS

在现有 flake 中添加名为 `emacs-jieba-rs` 的 input，URL 为
`git+https://codeberg.org/bingshan/emacs-jieba-rs.git`。将它加入 `outputs`
的参数集合，再将下面的模块加入 `nixosSystem` 的 `modules` 列表。它通过 overlay 将本包加入
`emacsPackagesFor`，并安装带有本包的 Emacs：

```nix
(
  {
    pkgs,
    ...
  }:
  {
    environment = {
      systemPackages = [
        (
          (pkgs.emacsPackagesFor pkgs.emacs-pgtk)
          .emacsWithPackages
          (epkgs: [ epkgs.jieba-rs ])
        )
      ];
    };

    nixpkgs = {
      overlays = [
        emacs-jieba-rs.overlays.default
      ];
    };
  }
)
```

overlay 没有预定义输出的系统限制，但其他平台需自行验证。安装后按上文启用次要模式。

## 开发与测试

源码位于 `lisp/` 和 `src/`，ERT 集成测试位于 `tests/`。在已安装源码构建工具的环境中，运行 `make check` 构建模块并执行
Cargo 和 ERT 测试。

使用 Nix 可分别运行：

```sh
nix flake check --all-systems
nix build .#jieba-rs-module
nix run .#emacs31-run-jieba-rs-tests
nix run .#emacs31-byte-compile-jieba-rs
nix run .#emacs31-checkdoc-jieba-rs
```

`nix flake check` 检查 flake 输出；ERT、字节编译和 Checkdoc 需要通过上述 `nix run` 命令执行。
`nix develop` 提供格式化和维护工具，不包含完整的 Rust、C 编译器和 Emacs 构建环境。

常用 Makefile 目标：

| 目标 | 用途 |
| -- | -- |
| `make`、`make module` | 构建 release 模块并复制到 `lisp/` |
| `make local` | 构建模块，生成包描述和自动加载文件 |
| `make pkg`、`make autoloads` | 分别生成包描述、自动加载文件 |
| `make test` | 构建模块并运行 ERT 测试 |
| `make check` | 构建模块并运行 Cargo、ERT 测试 |
| `make clean` | 删除 `lisp/` 生成文件和 `dist/`，保留 `target/` |

更新 Nix 依赖时，分别运行 `nix flake update` 和 `nix flake update --flake ./tools`，
更新根目录和维护工具的两份锁文件。

### 发布归档

`make release-archive` 生成 `dist/jieba-rs-VERSION.tar`，其中包含 Emacs 包和 Rust 模块。
二者共用版本号，模块不单独发布。发布相关目标还需要 `jq` 和 GNU tar。

- `make release-version`：检查 Emacs 包与 Rust crate 版本一致，并输出版本号。
- `make check-release-archive`：构建并校验归档，在隔离目录安装后执行分词验证。
- `make release-artifact`：构建归档并输出路径。

GitHub 发布工作流使用 Rust 1.88.0 在 Ubuntu 24.04 构建 `x86_64-unknown-linux-gnu` 归档，并使用
Emacs 31 验证安装。

## 相关项目

- [`jieba-rs`](https://github.com/messense/jieba-rs)：本项目使用的 Rust 中文分词库
- [`emacs-jieba`](https://github.com/kisaragi-hiu/emacs-jieba)：另一种 GNU Emacs
  Jieba 集成

## AI 辅助声明

本项目中的所有代码、测试和文档均在 AI 工具的辅助下开发。所有 AI 生成的内容均经过维护者审查，并在必要时进行了修改。维护者对最终内容负全部责任。未向 AI
工具有意提供任何机密信息、用户隐私数据或其他敏感信息。

## 项目许可证

`emacs-jieba-rs` 遵循 GNU GPL 第 3 版或更高版本，完整文本见 [`COPYING`](../COPYING)。本文档遵循 GNU
FDL 第 1.3 版或更高版本，完整文本见下节。

## GNU Free Documentation License

本文档遵循 GNU Free Documentation License 第 1.3 版或更高版本。

<details>
<summary>展开许可证全文</summary>

```text

                GNU Free Documentation License
                 Version 1.3, 3 November 2008


 Copyright (C) 2000, 2001, 2002, 2007, 2008 Free Software Foundation, Inc.
     <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

 0. PREAMBLE

 The purpose of this License is to make a manual, textbook, or other
 functional and useful document "free" in the sense of freedom: to
 assure everyone the effective freedom to copy and redistribute it,
 with or without modifying it, either commercially or noncommercially.
 Secondarily, this License preserves for the author and publisher a way
 to get credit for their work, while not being considered responsible
 for modifications made by others.

 This License is a kind of "copyleft", which means that derivative
 works of the document must themselves be free in the same sense.  It
 complements the GNU General Public License, which is a copyleft
 license designed for free software.

 We have designed this License in order to use it for manuals for free
 software, because free software needs free documentation: a free
 program should come with manuals providing the same freedoms that the
 software does.  But this License is not limited to software manuals;
 it can be used for any textual work, regardless of subject matter or
 whether it is published as a printed book.  We recommend this License
 principally for works whose purpose is instruction or reference.


 1. APPLICABILITY AND DEFINITIONS

 This License applies to any manual or other work, in any medium, that
 contains a notice placed by the copyright holder saying it can be
 distributed under the terms of this License.  Such a notice grants a
 world-wide, royalty-free license, unlimited in duration, to use that
 work under the conditions stated herein.  The "Document", below,
 refers to any such manual or work.  Any member of the public is a
 licensee, and is addressed as "you".  You accept the license if you
 copy, modify or distribute the work in a way requiring permission
 under copyright law.

 A "Modified Version" of the Document means any work containing the
 Document or a portion of it, either copied verbatim, or with
 modifications and/or translated into another language.

 A "Secondary Section" is a named appendix or a front-matter section of
 the Document that deals exclusively with the relationship of the
 publishers or authors of the Document to the Document's overall
 subject (or to related matters) and contains nothing that could fall
 directly within that overall subject.  (Thus, if the Document is in
 part a textbook of mathematics, a Secondary Section may not explain
 any mathematics.)  The relationship could be a matter of historical
 connection with the subject or with related matters, or of legal,
 commercial, philosophical, ethical or political position regarding
 them.

 The "Invariant Sections" are certain Secondary Sections whose titles
 are designated, as being those of Invariant Sections, in the notice
 that says that the Document is released under this License.  If a
 section does not fit the above definition of Secondary then it is not
 allowed to be designated as Invariant.  The Document may contain zero
 Invariant Sections.  If the Document does not identify any Invariant
 Sections then there are none.

 The "Cover Texts" are certain short passages of text that are listed,
 as Front-Cover Texts or Back-Cover Texts, in the notice that says that
 the Document is released under this License.  A Front-Cover Text may
 be at most 5 words, and a Back-Cover Text may be at most 25 words.

 A "Transparent" copy of the Document means a machine-readable copy,
 represented in a format whose specification is available to the
 general public, that is suitable for revising the document
 straightforwardly with generic text editors or (for images composed of
 pixels) generic paint programs or (for drawings) some widely available
 drawing editor, and that is suitable for input to text formatters or
 for automatic translation to a variety of formats suitable for input
 to text formatters.  A copy made in an otherwise Transparent file
 format whose markup, or absence of markup, has been arranged to thwart
 or discourage subsequent modification by readers is not Transparent.
 An image format is not Transparent if used for any substantial amount
 of text.  A copy that is not "Transparent" is called "Opaque".

 Examples of suitable formats for Transparent copies include plain
 ASCII without markup, Texinfo input format, LaTeX input format, SGML
 or XML using a publicly available DTD, and standard-conforming simple
 HTML, PostScript or PDF designed for human modification.  Examples of
 transparent image formats include PNG, XCF and JPG.  Opaque formats
 include proprietary formats that can be read and edited only by
 proprietary word processors, SGML or XML for which the DTD and/or
 processing tools are not generally available, and the
 machine-generated HTML, PostScript or PDF produced by some word
 processors for output purposes only.

 The "Title Page" means, for a printed book, the title page itself,
 plus such following pages as are needed to hold, legibly, the material
 this License requires to appear in the title page.  For works in
 formats which do not have any title page as such, "Title Page" means
 the text near the most prominent appearance of the work's title,
 preceding the beginning of the body of the text.

 The "publisher" means any person or entity that distributes copies of
 the Document to the public.

 A section "Entitled XYZ" means a named subunit of the Document whose
 title either is precisely XYZ or contains XYZ in parentheses following
 text that translates XYZ in another language.  (Here XYZ stands for a
 specific section name mentioned below, such as "Acknowledgements",
 "Dedications", "Endorsements", or "History".)  To "Preserve the Title"
 of such a section when you modify the Document means that it remains a
 section "Entitled XYZ" according to this definition.

 The Document may include Warranty Disclaimers next to the notice which
 states that this License applies to the Document.  These Warranty
 Disclaimers are considered to be included by reference in this
 License, but only as regards disclaiming warranties: any other
 implication that these Warranty Disclaimers may have is void and has
 no effect on the meaning of this License.

 2. VERBATIM COPYING

 You may copy and distribute the Document in any medium, either
 commercially or noncommercially, provided that this License, the
 copyright notices, and the license notice saying this License applies
 to the Document are reproduced in all copies, and that you add no
 other conditions whatsoever to those of this License.  You may not use
 technical measures to obstruct or control the reading or further
 copying of the copies you make or distribute.  However, you may accept
 compensation in exchange for copies.  If you distribute a large enough
 number of copies you must also follow the conditions in section 3.

 You may also lend copies, under the same conditions stated above, and
 you may publicly display copies.


 3. COPYING IN QUANTITY

 If you publish printed copies (or copies in media that commonly have
 printed covers) of the Document, numbering more than 100, and the
 Document's license notice requires Cover Texts, you must enclose the
 copies in covers that carry, clearly and legibly, all these Cover
 Texts: Front-Cover Texts on the front cover, and Back-Cover Texts on
 the back cover.  Both covers must also clearly and legibly identify
 you as the publisher of these copies.  The front cover must present
 the full title with all words of the title equally prominent and
 visible.  You may add other material on the covers in addition.
 Copying with changes limited to the covers, as long as they preserve
 the title of the Document and satisfy these conditions, can be treated
 as verbatim copying in other respects.

 If the required texts for either cover are too voluminous to fit
 legibly, you should put the first ones listed (as many as fit
 reasonably) on the actual cover, and continue the rest onto adjacent
 pages.

 If you publish or distribute Opaque copies of the Document numbering
 more than 100, you must either include a machine-readable Transparent
 copy along with each Opaque copy, or state in or with each Opaque copy
 a computer-network location from which the general network-using
 public has access to download using public-standard network protocols
 a complete Transparent copy of the Document, free of added material.
 If you use the latter option, you must take reasonably prudent steps,
 when you begin distribution of Opaque copies in quantity, to ensure
 that this Transparent copy will remain thus accessible at the stated
 location until at least one year after the last time you distribute an
 Opaque copy (directly or through your agents or retailers) of that
 edition to the public.

 It is requested, but not required, that you contact the authors of the
 Document well before redistributing any large number of copies, to
 give them a chance to provide you with an updated version of the
 Document.


 4. MODIFICATIONS

 You may copy and distribute a Modified Version of the Document under
 the conditions of sections 2 and 3 above, provided that you release
 the Modified Version under precisely this License, with the Modified
 Version filling the role of the Document, thus licensing distribution
 and modification of the Modified Version to whoever possesses a copy
 of it.  In addition, you must do these things in the Modified Version:

 A. Use in the Title Page (and on the covers, if any) a title distinct
    from that of the Document, and from those of previous versions
    (which should, if there were any, be listed in the History section
    of the Document).  You may use the same title as a previous version
    if the original publisher of that version gives permission.
 B. List on the Title Page, as authors, one or more persons or entities
    responsible for authorship of the modifications in the Modified
    Version, together with at least five of the principal authors of the
    Document (all of its principal authors, if it has fewer than five),
    unless they release you from this requirement.
 C. State on the Title page the name of the publisher of the
    Modified Version, as the publisher.
 D. Preserve all the copyright notices of the Document.
 E. Add an appropriate copyright notice for your modifications
    adjacent to the other copyright notices.
 F. Include, immediately after the copyright notices, a license notice
    giving the public permission to use the Modified Version under the
    terms of this License, in the form shown in the Addendum below.
 G. Preserve in that license notice the full lists of Invariant Sections
    and required Cover Texts given in the Document's license notice.
 H. Include an unaltered copy of this License.
 I. Preserve the section Entitled "History", Preserve its Title, and add
    to it an item stating at least the title, year, new authors, and
    publisher of the Modified Version as given on the Title Page.  If
    there is no section Entitled "History" in the Document, create one
    stating the title, year, authors, and publisher of the Document as
    given on its Title Page, then add an item describing the Modified
    Version as stated in the previous sentence.
 J. Preserve the network location, if any, given in the Document for
    public access to a Transparent copy of the Document, and likewise
    the network locations given in the Document for previous versions
    it was based on.  These may be placed in the "History" section.
    You may omit a network location for a work that was published at
    least four years before the Document itself, or if the original
    publisher of the version it refers to gives permission.
 K. For any section Entitled "Acknowledgements" or "Dedications",
    Preserve the Title of the section, and preserve in the section all
    the substance and tone of each of the contributor acknowledgements
    and/or dedications given therein.
 L. Preserve all the Invariant Sections of the Document,
    unaltered in their text and in their titles.  Section numbers
    or the equivalent are not considered part of the section titles.
 M. Delete any section Entitled "Endorsements".  Such a section
    may not be included in the Modified Version.
 N. Do not retitle any existing section to be Entitled "Endorsements"
    or to conflict in title with any Invariant Section.
 O. Preserve any Warranty Disclaimers.

 If the Modified Version includes new front-matter sections or
 appendices that qualify as Secondary Sections and contain no material
 copied from the Document, you may at your option designate some or all
 of these sections as invariant.  To do this, add their titles to the
 list of Invariant Sections in the Modified Version's license notice.
 These titles must be distinct from any other section titles.

 You may add a section Entitled "Endorsements", provided it contains
 nothing but endorsements of your Modified Version by various
 parties--for example, statements of peer review or that the text has
 been approved by an organization as the authoritative definition of a
 standard.

 You may add a passage of up to five words as a Front-Cover Text, and a
 passage of up to 25 words as a Back-Cover Text, to the end of the list
 of Cover Texts in the Modified Version.  Only one passage of
 Front-Cover Text and one of Back-Cover Text may be added by (or
 through arrangements made by) any one entity.  If the Document already
 includes a cover text for the same cover, previously added by you or
 by arrangement made by the same entity you are acting on behalf of,
 you may not add another; but you may replace the old one, on explicit
 permission from the previous publisher that added the old one.

 The author(s) and publisher(s) of the Document do not by this License
 give permission to use their names for publicity for or to assert or
 imply endorsement of any Modified Version.


 5. COMBINING DOCUMENTS

 You may combine the Document with other documents released under this
 License, under the terms defined in section 4 above for modified
 versions, provided that you include in the combination all of the
 Invariant Sections of all of the original documents, unmodified, and
 list them all as Invariant Sections of your combined work in its
 license notice, and that you preserve all their Warranty Disclaimers.

 The combined work need only contain one copy of this License, and
 multiple identical Invariant Sections may be replaced with a single
 copy.  If there are multiple Invariant Sections with the same name but
 different contents, make the title of each such section unique by
 adding at the end of it, in parentheses, the name of the original
 author or publisher of that section if known, or else a unique number.
 Make the same adjustment to the section titles in the list of
 Invariant Sections in the license notice of the combined work.

 In the combination, you must combine any sections Entitled "History"
 in the various original documents, forming one section Entitled
 "History"; likewise combine any sections Entitled "Acknowledgements",
 and any sections Entitled "Dedications".  You must delete all sections
 Entitled "Endorsements".


 6. COLLECTIONS OF DOCUMENTS

 You may make a collection consisting of the Document and other
 documents released under this License, and replace the individual
 copies of this License in the various documents with a single copy
 that is included in the collection, provided that you follow the rules
 of this License for verbatim copying of each of the documents in all
 other respects.

 You may extract a single document from such a collection, and
 distribute it individually under this License, provided you insert a
 copy of this License into the extracted document, and follow this
 License in all other respects regarding verbatim copying of that
 document.


 7. AGGREGATION WITH INDEPENDENT WORKS

 A compilation of the Document or its derivatives with other separate
 and independent documents or works, in or on a volume of a storage or
 distribution medium, is called an "aggregate" if the copyright
 resulting from the compilation is not used to limit the legal rights
 of the compilation's users beyond what the individual works permit.
 When the Document is included in an aggregate, this License does not
 apply to the other works in the aggregate which are not themselves
 derivative works of the Document.

 If the Cover Text requirement of section 3 is applicable to these
 copies of the Document, then if the Document is less than one half of
 the entire aggregate, the Document's Cover Texts may be placed on
 covers that bracket the Document within the aggregate, or the
 electronic equivalent of covers if the Document is in electronic form.
 Otherwise they must appear on printed covers that bracket the whole
 aggregate.


 8. TRANSLATION

 Translation is considered a kind of modification, so you may
 distribute translations of the Document under the terms of section 4.
 Replacing Invariant Sections with translations requires special
 permission from their copyright holders, but you may include
 translations of some or all Invariant Sections in addition to the
 original versions of these Invariant Sections.  You may include a
 translation of this License, and all the license notices in the
 Document, and any Warranty Disclaimers, provided that you also include
 the original English version of this License and the original versions
 of those notices and disclaimers.  In case of a disagreement between
 the translation and the original version of this License or a notice
 or disclaimer, the original version will prevail.

 If a section in the Document is Entitled "Acknowledgements",
 "Dedications", or "History", the requirement (section 4) to Preserve
 its Title (section 1) will typically require changing the actual
 title.


 9. TERMINATION

 You may not copy, modify, sublicense, or distribute the Document
 except as expressly provided under this License.  Any attempt
 otherwise to copy, modify, sublicense, or distribute it is void, and
 will automatically terminate your rights under this License.

 However, if you cease all violation of this License, then your license
 from a particular copyright holder is reinstated (a) provisionally,
 unless and until the copyright holder explicitly and finally
 terminates your license, and (b) permanently, if the copyright holder
 fails to notify you of the violation by some reasonable means prior to
 60 days after the cessation.

 Moreover, your license from a particular copyright holder is
 reinstated permanently if the copyright holder notifies you of the
 violation by some reasonable means, this is the first time you have
 received notice of violation of this License (for any work) from that
 copyright holder, and you cure the violation prior to 30 days after
 your receipt of the notice.

 Termination of your rights under this section does not terminate the
 licenses of parties who have received copies or rights from you under
 this License.  If your rights have been terminated and not permanently
 reinstated, receipt of a copy of some or all of the same material does
 not give you any rights to use it.


 10. FUTURE REVISIONS OF THIS LICENSE

 The Free Software Foundation may publish new, revised versions of the
 GNU Free Documentation License from time to time.  Such new versions
 will be similar in spirit to the present version, but may differ in
 detail to address new problems or concerns.  See
 https://www.gnu.org/licenses/.

 Each version of the License is given a distinguishing version number.
 If the Document specifies that a particular numbered version of this
 License "or any later version" applies to it, you have the option of
 following the terms and conditions either of that specified version or
 of any later version that has been published (not as a draft) by the
 Free Software Foundation.  If the Document does not specify a version
 number of this License, you may choose any version ever published (not
 as a draft) by the Free Software Foundation.  If the Document
 specifies that a proxy can decide which future versions of this
 License can be used, that proxy's public statement of acceptance of a
 version permanently authorizes you to choose that version for the
 Document.

 11. RELICENSING

 "Massive Multiauthor Collaboration Site" (or "MMC Site") means any
 World Wide Web server that publishes copyrightable works and also
 provides prominent facilities for anybody to edit those works.  A
 public wiki that anybody can edit is an example of such a server.  A
 "Massive Multiauthor Collaboration" (or "MMC") contained in the site
 means any set of copyrightable works thus published on the MMC site.

 "CC-BY-SA" means the Creative Commons Attribution-Share Alike 3.0
 license published by Creative Commons Corporation, a not-for-profit
 corporation with a principal place of business in San Francisco,
 California, as well as future copyleft versions of that license
 published by that same organization.

 "Incorporate" means to publish or republish a Document, in whole or in
 part, as part of another Document.

 An MMC is "eligible for relicensing" if it is licensed under this
 License, and if all works that were first published under this License
 somewhere other than this MMC, and subsequently incorporated in whole or
 in part into the MMC, (1) had no cover texts or invariant sections, and
 (2) were thus incorporated prior to November 1, 2008.

 The operator of an MMC Site may republish an MMC contained in the site
 under CC-BY-SA on the same site at any time before August 1, 2009,
 provided the MMC is eligible for relicensing.


 ADDENDUM: How to use this License for your documents

 To use this License in a document you have written, include a copy of
 the License in the document and put the following copyright and
 license notices just after the title page:

     Copyright (c)  YEAR  YOUR NAME.
     Permission is granted to copy, distribute and/or modify this document
     under the terms of the GNU Free Documentation License, Version 1.3
     or any later version published by the Free Software Foundation;
     with no Invariant Sections, no Front-Cover Texts, and no Back-Cover Texts.
     A copy of the license is included in the section entitled "GNU
     Free Documentation License".

 If you have Invariant Sections, Front-Cover Texts and Back-Cover Texts,
 replace the "with...Texts." line with this:

     with the Invariant Sections being LIST THEIR TITLES, with the
     Front-Cover Texts being LIST, and with the Back-Cover Texts being LIST.

 If you have Invariant Sections without Cover Texts, or some other
 combination of the three, merge those two alternatives to suit the
 situation.

 If your document contains nontrivial examples of program code, we
 recommend releasing these examples in parallel under your choice of
 free software license, such as the GNU General Public License,
 to permit their use in free software.

```

</details>
