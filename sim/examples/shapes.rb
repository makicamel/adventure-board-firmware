# VRAM の描画 API。線と矩形。
# VRAM は 1bit なので、明るさは blit の on: で決める。
matrix.clear
matrix.clear_drawing
matrix.draw_rect(0, 0, 16, 16, 1)
matrix.draw_line(0, 0, 15, 15, 1)
matrix.draw_line(15, 0, 0, 15, 1)
matrix.blit(on: 0x80)
matrix.show
