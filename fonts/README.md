# フォント

- `BIZUDGothic-Regular.ttf` — BIZ UDゴシック(モリサワ)。SIL Open Font License 1.1(`OFL.txt`)
  - 入手元: https://github.com/googlefonts/morisawa-biz-ud-gothic (`fonts/ttf/BIZUDGothic-Regular.ttf`)
  - Godot 3 の標準フォントには日本語の文字が無く、HUD の日本語が表示されないため同梱(Godot 4 でも字形をそろえるため引き続き使う)
  - 等幅(P なし)を選んだのは、HUD の座標表示(`X:%6.1f`)の桁をそろえるため
- `NotoSans-Ruble.ttf` — Noto Sans Regular から `₽`(U+20BD)だけを切り出したもの。SIL Open Font License 1.1(`OFL-NotoSans.txt`)
  - 入手元: https://github.com/notofonts/notofonts.github.io (`fonts/NotoSans/hinted/ttf/NotoSans-Regular.ttf`)
  - BIZ UDゴシックに `₽` が無く、Web 版ではシステムフォントの代わりも使えないため同梱
  - 切り出し: `pyftsubset NotoSans-Regular.ttf --unicodes=U+20BD --output-file=NotoSans-Ruble.ttf`
  - 縦の寸法(ascent・descent)は BIZ UDゴシックと同じ比率に書き換えている。Godot の行の高さは補う側のフォントも含めた最大値になるので、そのままだと HUD の行間が広がる
- `hud_theme.tres` — BIZ UDゴシック(14px)を既定にし、無い文字を `NotoSans-Ruble.ttf` で補う Theme。`project.godot` の `gui/theme/custom` に設定している
