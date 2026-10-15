# Attribution

## Research and code

This project is a port of **Generative Agents: Interactive Simulacra of Human Behavior** (Park, O'Brien, Cai, Morris, Liang, Bernstein; UIST '23). The original code is at <https://github.com/joonspk-research/generative_agents> under the Apache License 2.0. The agent architecture (memory stream, retrieval scoring, reflection, planning), the Smallville town layout, the 25 personas and the Valentine's Day scenario come from that work. See `NOTICE`.

Please cite the paper if you use this project in research:

```
@inproceedings{Park2023GenerativeAgents,
  author = {Park, Joon Sung and O'Brien, Joseph C. and Cai, Carrie J. and Morris, Meredith Ringel and Liang, Percy and Bernstein, Michael S.},
  title = {Generative Agents: Interactive Simulacra of Human Behavior},
  year = {2023},
  booktitle = {In the 36th Annual ACM Symposium on User Interface Software and Technology (UIST '23)},
  publisher = {Association for Computing Machinery},
  address = {New York, NY, USA}
}
```

## Art

The original Smallville art is **not** included in this repository and is not covered by this project's license. The Stanford README credits:

- Background art: PixyMoon (@_PixyMoon_)
- Furniture / interior design: LimeZu (@lime_px) — <https://limezu.itch.io>
- Character design: ぴぽ / pipoya (@pipohi) — <https://pipoya.itch.io>

`scripts/fetch-assets.sh` copies these files from your own clone of the Stanford repository into `Assets/ThirdParty/`, which is gitignored. Whether you may use them depends on each artist's terms, which you should read yourself. Support the artists if you use their work.

Permission status (update as answers arrive):

| Asset | Status |
| --- | --- |
| LimeZu interiors/exteriors | not yet asked |
| pipoya characters | not yet asked |
| PixyMoon background | not yet asked |

Fallback if permission isn't granted: re-skin with CC0 (Kenney) or LPC (CC-BY-SA) assets; the map's logical layers (collision, sector, arena, object) are data from the Apache-2.0 repository and are reused either way.
