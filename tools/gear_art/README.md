# Gear art (approved look, 2026-10-01)

Source: Viollet-le-Duc, *Dictionnaire raisonné du mobilier français* (1873-74), tome 5, via Wikimedia Commons (public domain). Files in `source/`.

- `prep.py`: crop, mask plate letters and signatures, remove bleed-through (levels 55..200).
- `page.py`: item detail mockup, 758x1024, 16 grays.
- `ladder.py`: rarity ladder on the sword (needs `sword_lv_170.png`: crop (295,118,760,2410) of source/sword.png, levels 60..170).

Rarity ladder (Mike approved): Common bare; Uncommon leather-wrapped grip; Rare faceted stone in the pommel; Epic gilding (stipple) on guard and pommel; Legendary second stone at the guard plus engraved rays behind the hilt.
Rejected: etchings on the blade (runes, frost) - "looks bad". Long weapons shown as a diagonal close-up, blade running off the frame.

Style stones (Mike approved 2026-10-01): the Rare+ pommel stone shows the build style, drawn square to the sword so it turns with it. `ladder.page(rarity, title, stats, style)`: plain = faceted gem; rime = six-point star cut; affliction = serpent's eye with slit pupil; retribution = ring of thorns; blood = pointed drop; riposte = crossed swords at 90 degrees. Not yet wired into build_plugin.py or the plugin.

Crop boxes (rule added 2026-10-05): measure them from the image's own pixels (dark-pixel bounding box, e.g. on a canvas or with PIL), never by reading positions off a browser screenshot. Screenshots from the browser tools are scaled unevenly, so boxes read off them come out wrong vertically. Record boxes as fractions of the page image.
