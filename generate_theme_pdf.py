"""Generate a PDF showing the BlockPro theme colour palette."""

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, white, black

OUTPUT = "blockpro_theme_colours.pdf"
PAGE_W, PAGE_H = A4

# ── Colour data from app_palettes.dart ──────────────────────────────────

LIGHT = [
    ("Primary",           "#345799"),
    ("Primary Container", "#D4DFEF"),
    ("Secondary",         "#3A63B5"),
    ("Secondary Container","#D6E0F2"),
    ("Tertiary",          "#43B86A"),
    ("Tertiary Container","#C8F0D4"),
    ("Error",             "#C13F39"),
    ("Error Container",   "#FCDAD8"),
]

DARK = [
    ("Primary",           "#A8C4E8"),
    ("Primary Container", "#1E3A66"),
    ("Secondary",         "#9BB8E8"),
    ("Secondary Container","#1E3566"),
    ("Tertiary",          "#8EDDA6"),
    ("Tertiary Container","#1E7A3E"),
    ("Error",             "#F0918C"),
    ("Error Container",   "#7A1F1B"),
]


def luminance(hex_color: str) -> float:
    """Return relative luminance of a hex colour."""
    r, g, b = int(hex_color[1:3], 16), int(hex_color[3:5], 16), int(hex_color[5:7], 16)
    def lin(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def text_color(hex_color: str):
    """Return white or black depending on background luminance."""
    return white if luminance(hex_color) < 0.4 else black


MARGIN = 20 * mm
SWATCH_W = 78 * mm
SWATCH_H = 18 * mm
GAP = 3 * mm
COLS = 2


def draw_footer(c):
    c.setFillColor(HexColor("#999999"))
    c.setFont("Helvetica", 8)
    c.drawString(MARGIN, 10 * mm, "Generated from flutter/lib/theme/app_palettes.dart")
    c.drawRightString(PAGE_W - MARGIN, 10 * mm, "BlockPro  \u00b7  FlexColorScheme M3")


def draw_section(c, title, colors, y_start):
    """Draw a titled section with colour swatches."""
    row_h = SWATCH_H + GAP

    y = y_start
    c.setFont("Helvetica-Bold", 16)
    c.setFillColor(black)
    c.drawString(MARGIN, y, title)
    y -= 8 * mm

    for i, (name, hex_val) in enumerate(colors):
        col = i % COLS
        x = MARGIN + col * (SWATCH_W + GAP)

        if col == 0:
            current_row_y = y
        sy = current_row_y

        # Draw swatch rectangle
        c.setFillColor(HexColor(hex_val))
        c.setStrokeColor(HexColor("#CCCCCC"))
        c.setLineWidth(0.5)
        c.roundRect(x, sy - SWATCH_H, SWATCH_W, SWATCH_H, 5, fill=1, stroke=1)

        # Colour name inside swatch
        tc = text_color(hex_val)
        c.setFillColor(tc)
        c.setFont("Helvetica-Bold", 10)
        c.drawString(x + 5 * mm, sy - 8 * mm, name)

        # Hex value inside swatch
        c.setFont("Helvetica", 9)
        c.drawString(x + 5 * mm, sy - 15 * mm, hex_val.upper())

        # After the last column in a row, move y down
        if col == COLS - 1:
            y = current_row_y - row_h

    # If the last row wasn't complete, still move y down
    if len(colors) % COLS != 0:
        y = current_row_y - row_h

    return y


def main():
    c = canvas.Canvas(OUTPUT, pagesize=A4)

    # ── Header ──────────────────────────────────────────────────────────
    y = PAGE_H - 20 * mm

    # Title bar
    c.setFillColor(HexColor("#345799"))
    c.rect(0, y - 2 * mm, PAGE_W, 16 * mm, fill=1, stroke=0)
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 22)
    c.drawString(MARGIN, y + 1 * mm, "BlockPro Theme Colours")

    # Subtitle
    y -= 12 * mm
    c.setFillColor(HexColor("#555555"))
    c.setFont("Helvetica", 10)
    c.drawString(MARGIN, y, "Brand blues with green and red accents  \u00b7  Material 3 seed colours")

    y -= 12 * mm

    # ── Light theme section ─────────────────────────────────────────────
    y = draw_section(c, "Light Theme", LIGHT, y)

    y -= 6 * mm

    # ── Dark theme section ──────────────────────────────────────────────
    y = draw_section(c, "Dark Theme", DARK, y)

    # ── Footer ──────────────────────────────────────────────────────────
    draw_footer(c)

    c.save()
    print(f"PDF saved to {OUTPUT}")


if __name__ == "__main__":
    main()
