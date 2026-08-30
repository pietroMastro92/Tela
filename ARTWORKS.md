# Artwork credits

Tela bundles faithful digital reproductions whose individual source files are marked public domain, CC0 or CC BY on Wikimedia Commons. The images are normalized at build time, stored locally, and the app never contacts Wikimedia or museums at runtime.

| Asset | Work | Source | Rights |
| --- | --- | --- | --- |
| `MonetWaterLilies` | Claude Monet, *Water Lilies*, 1906 | [Art Institute of Chicago, 16568](https://www.artic.edu/artworks/16568/water-lilies) | CC0 / Public Domain |
| `VanGoghBedroom` | Vincent van Gogh, *The Bedroom*, 1889 | [Art Institute of Chicago, 28560](https://www.artic.edu/artworks/28560/the-bedroom) | CC0 / Public Domain |
| `HokusaiGreatWave` | Katsushika Hokusai, *The Great Wave*, ca. 1830–32 | [The Metropolitan Museum of Art, 56353](https://www.metmuseum.org/art/collection/search/56353) | Open Access / Public Domain |

The Monet and Van Gogh JPEG files were downloaded from the corresponding Wikimedia Commons public-domain file records because the museum IIIF endpoint blocks automated downloads. The Hokusai JPEG was downloaded directly from The Met Open Access image endpoint.

## Gustav Klimt

The `Klimt` shelf contains 16 works: *The Kiss*, *Portrait of Adele Bloch-Bauer I*, *Judith I*, *Danaë*, *Death and Life*, *The Three Ages of Woman*, *Beethoven Frieze: The Hostile Powers*, *Portrait of Emilie Flöge*, *Pallas Athena*, *Hope II*, *The Maiden*, *Water Serpents II*, *The Tree of Life*, *Rosebushes Under the Trees*, *Sunflower*, and *Avenue at Schloss Kammer*.

## Gli occhi di Monna Lisa

The dedicated shelf follows Thomas Schlesser's 52-work itinerary. Tela includes the 36 works for which a suitable open reproduction was verified: chapters 1–35 plus chapter 37, with Klimt's *Rosebushes Under the Trees* shared by both shelves.

The remaining 16 contemporary works are not silently copied from museum pages. Their metadata and official Centre Pompidou links are kept in `Tela/Resources/MonaLisaRightsStatus.json`, ready for licensed images in a future release. This catalog is an independent reading companion and is not affiliated with Thomas Schlesser, Longanesi, Albin Michel, or the museums.

Exact Wikimedia file pages, download URLs, dimensions, creator credit, and the machine-read license captured for all 51 new assets are in `Tela/Resources/ArtworkDownloadReport.json`. `Scripts/public_domain_artworks.json` is the curated catalog and `Scripts/fetch_public_domain_artworks.py` rebuilds the local imagesets. The fetcher uses a descriptive user agent, serial requests, retry-after handling, and exponential backoff.
