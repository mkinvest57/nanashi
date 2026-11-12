"""Regenerate the static phone handoff code with qrcode==8.2 (development only)."""

from pathlib import Path

import qrcode
from qrcode.image.svg import SvgPathFillImage


INSTALL_URL = "https://nanashi-mk.vercel.app/#installer"
SETUP_URL = "https://nanashi-mk.vercel.app/installation-sidestore"


def make_code(url=INSTALL_URL):
    code = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=8, border=4)
    code.add_data(url)
    code.make(fit=True)
    return code


if __name__ == "__main__":
    for filename, url in (("install-qr.svg", INSTALL_URL), ("sidestore-setup-qr.svg", SETUP_URL)):
        destination = Path(__file__).resolve().parents[1] / "public" / filename
        make_code(url).make_image(image_factory=SvgPathFillImage).save(destination)
        print(f"Generated {destination.name} for {url}")
