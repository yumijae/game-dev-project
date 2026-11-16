"""Downloads the CC0 3D props used to furnish the school from Poly Haven.

    python tools/fetch_models.py

Saves glTF models (1k textures) to models/polyhaven/<asset>/.
All Poly Haven assets are CC0 (public domain): https://polyhaven.com/license
"""
import json
import os
import sys
import urllib.request

ASSETS = [
    # classrooms
    "SchoolDesk_01", "SchoolChair_01", "ceiling_fan", "wall_clock",
    # offices / faculty / director / staff
    "metal_office_desk", "drawer_cabinet", "dining_chair_02", "modern_arm_chair_01",
    "Sofa_01", "modern_coffee_table_01", "wooden_bookshelf_worn", "CoffeeCart_01",
    "classic_laptop", "office_notepads", "stationery_supplies",
    # seating everywhere (the classic monobloc)
    "plastic_monobloc_chair_01",
    # storage / records / pantry / server / MIT
    "steel_frame_shelves_01", "cardboard_box_01", "plastic_crate_01", "tool_cart", "metal_toolbox",
    # kitchen / dining
    "electric_stove", "vintage_microwave", "pot_enamel_01", "wooden_cutting_board", "round_wooden_table_01",
    # building services & security (useful for a looting game)
    "mounted_fluorescent_lights", "fire_alarm", "security_camera_01", "metal_trash_can",
    # restrooms
    "plunger", "plastic_broom",
    # lobby + outside
    "painted_wooden_bench", "planter_box_01", "anthurium_botany_01", "street_lamp_01",
    # replacements for the generator's placeholder boxes
    "dining_table", "binder_notebook", "planter_box_02", "potted_plant_01",
]
RES = "1k"
UA = {"User-Agent": "godot-school-model-fetch"}
ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "models", "polyhaven")


def get_json(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return json.load(r)


def download(url, dest):
    if os.path.exists(dest):
        return 0
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=180) as r, open(dest, "wb") as f:
        data = r.read()
        f.write(data)
        return len(data)


def main():
    total = 0
    index = {}
    for asset in ASSETS:
        files = get_json(f"https://api.polyhaven.com/files/{asset}")
        g = files["gltf"][RES]["gltf"]
        out = os.path.join(ROOT, asset)
        n = download(g["url"], os.path.join(out, f"{asset}.gltf"))
        for rel, inc in g.get("include", {}).items():
            n += download(inc["url"], os.path.join(out, rel.replace("/", os.sep)))
        total += n
        index[asset] = f"res://models/polyhaven/{asset}/{asset}.gltf"
        print(f"{asset:30s} {n / 1e6:6.1f} MB")
    with open(os.path.join(ROOT, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, indent=1)
    with open(os.path.join(ROOT, "LICENSE.txt"), "w", encoding="utf-8") as f:
        f.write("3D models from Poly Haven (https://polyhaven.com), licensed CC0 1.0 (public domain).\n"
                "No attribution required. Assets: " + ", ".join(ASSETS) + "\n")
    print(f"downloaded {total / 1e6:.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
