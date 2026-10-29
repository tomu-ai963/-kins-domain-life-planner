# フォント

- `BIZUDGothic-Regular.ttf` — BIZ UDゴシック(モリサワ)。SIL Open Font License 1.1(`OFL.txt`)
  - 入手元: https://github.com/googlefonts/morisawa-biz-ud-gothic (`fonts/ttf/BIZUDGothic-Regular.ttf`)
  - Godot 3 の標準フォントには日本語の文字が無く、HUD の日本語が表示されないため同梱
  - 等幅(P なし)を選んだのは、HUD の座標表示(`X:%6.1f`)の桁をそろえるため
- `hud_font.tres` — 上のフォントを使う DynamicFont。`project.godot` の `gui/theme/custom_font` に設定している
