"""Regenerate the static phone handoff code with qrcode==8.2 (development only)."""

from pathlib import Path

import qrcode
from qrcode.image.svg import SvgPathFillImage


INSTALL_URL = "https://nanashi-mk.vercel.app/#installer"


def make_code():
    code = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=8, border=4)
    code.add_data(INSTALL_URL)
    code.make(fit=True)
    return code


if __name__ == "__main__":
    destination = Path(__file__).resolve().parents[1] / "public" / "install-qr.svg"
    make_code().make_image(image_factory=SvgPathFillImage).save(destination)
    print(f"Generated {destination.name} for {INSTALL_URL}")
