"""Regenerate the static phone handoff codes with qrcode==8.2 (development only)."""

from pathlib import Path

import qrcode
from qrcode.image.svg import SvgPathFillImage


INSTALL_URL = "https://nanashi-mk.vercel.app/#installer"
SETUP_URL = "https://nanashi-mk.vercel.app/installation-sidestore"
IPHONE_URL = SETUP_URL + "?step=prepare#setup-step-heading"
AUTOMATION_URL = SETUP_URL + "?step=automation#setup-step-heading"
NANASHI_IPHONE_URL = "https://nanashi-mk.vercel.app/installation-nanashi?step=iphone#installation-etape"

QR_DESTINATIONS = (
    ("install-qr.svg", INSTALL_URL),
    ("sidestore-setup-qr.svg", SETUP_URL),
    ("sidestore-iphone-qr.svg", IPHONE_URL),
    ("sidestore-automation-qr.svg", AUTOMATION_URL),
    ("nanashi-iphone-qr.svg", NANASHI_IPHONE_URL),
)


def make_code(url=INSTALL_URL):
    code = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=8, border=4)
    code.add_data(url)
    code.make(fit=True)
    return code


if __name__ == "__main__":
    for filename, url in QR_DESTINATIONS:
        destination = Path(__file__).resolve().parents[1] / "public" / filename
        make_code(url).make_image(image_factory=SvgPathFillImage).save(destination)
        print(f"Generated {destination.name} for {url}")
