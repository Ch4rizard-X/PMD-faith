# Shader packs (3D view)

The dungeons can be played in a 3D voxel view (**Game Options → 3D View → View: 3D**). Its look comes from a
**shader pack**. Fourteen packs are built in, and you can make your own.

## Built-in packs

| Pack | Look |
|---|---|
| Off | The plain voxel view, no effects (fastest). |
| Classic | GBA colours, outlines, gentle grass sway and water. |
| Soft | A cosy diorama: soft light, soft shadows, corner shading. |
| Vibrant | Punchy colours, strong glow, shiny water. |
| Cinematic | Tinted, distant fog, deep shadows, strong torch light on dark floors. |
| Retro | Low resolution, 16-colour palette, scanlines. |
| Toon | Cel shading with thick outlines. |
| Claymation | Matte, soft, slightly warm. |
| Miniature | Tilt-shift blur: dungeons look like toy sets. |
| Storybook | Paper texture, muted colours, brown ink. |
| Neon Night | Dark scenes, glowing outlines, bright lava. |
| Golden Hour | Low warm sun, long shadows. |
| Monochrome | Black and white film with grain. |
| Dream | Pastel haze and bloom. |

Every pack can be adjusted on the same page: sunlight, warmth, shadows, saturation, contrast, brightness, tint,
palette, outlines, grass sway and density, water, waves, lava glow, torch light, glow, fog, corner shading,
depth of field, film grain, vignette, scanlines, colour fringe, 3D weather, resolution, and a Performance preset
(Battery / Balanced / Quality). Any row left on **Pack** uses the pack's own value.

- **Pack per dungeon: Auto** picks Cinematic on dark floors, Neon Night in crystal caves, Soft on snow and
  clouds, and Golden Hour in deserts; other dungeons keep your pack.
- **Save as my pack** stores your current settings as a new pack.
- Quick keys in a dungeon: **V** next pack, **Shift+V** 2D / 3D (controller: **Select+R**, **Select+L**).

## Making a pack

A pack is a JSON file in the game's user folder, in `shaderpacks/`:

- Windows: `%APPDATA%\Godot\app_userdata\PMD Red Rescue Team\shaderpacks\`
- Android: `Android/data/<package>/files/shaderpacks/`

```json
{
  "name": "Sunset Caves",
  "base": "Golden Hour",
  "settings": {
    "sat": 1.2,
    "tint": "#ffb070",
    "tint_amt": 0.2,
    "outline": 0.25,
    "torch": 3.0,
    "fog": 1,
    "fog_amt": 0.4
  }
}
```

`base` is a built-in pack to start from; `settings` changes any of these:

| Key | Meaning | Neutral |
|---|---|---|
| `sun`, `sun_pitch`, `sun_yaw`, `sun_col` | sunlight strength, angle (degrees), colour | 0.9, 52, -35, `#fff5e0` |
| `ambient`, `amb_col` | fill light | 0.35 |
| `shadows` | 0 off, 1 soft, 2 hard | 1 |
| `sat`, `contrast`, `bright` | colour grading | 1.0 |
| `tint`, `tint_amt` | colour tint and its strength | white, 0 |
| `palette` | colour limit (0 = full, 8 / 16 / 32) | 0 |
| `mono` | 1 black and white, 2 sepia | 0 |
| `outline`, `outline_all`, `ink`, `neon`, `edge_glow` | outline thickness, colour, glowing outlines | 0.15 |
| `toon`, `wrap` | cel-shading bands, soft "clay" light | 0, 0 |
| `sway`, `grass` | grass sway strength, blade density (0-1) | 0.55, 0.22 |
| `water_alpha`, `waves` | water opacity, wave strength | 0.72, 1.0 |
| `lava`, `glow` | lava glow, bloom | 1.0, 0.45 |
| `torch`, `torch_col` | light radius on dark floors (tiles), colour | 2.6 |
| `fog`, `fog_amt`, `fog_col` | 0 off, 1 distance, 2 height | 0 |
| `ao` | corner shading | 0.35 |
| `dof`, `dof_amt` | 1 tilt-shift, 2 background blur | 0 |
| `haze`, `paper`, `grain`, `vignette`, `scan`, `ca` | screen effects | 0 |
| `weather` | 3D rain / snow: 0 off, 1 on, 2 heavy | 1 |
| `res` | render resolution (0.5-1.0) | 1.0 |

### Your own shader

A pack can replace the screen pass with its own Godot `canvas_item` shader, given as a string in
`"post_shader"`. It reads the 3D view through a `hint_screen_texture` sampler:

```json
{
  "name": "Night vision",
  "base": "Classic",
  "post_shader": "shader_type canvas_item;\nuniform sampler2D screen : hint_screen_texture;\nvoid fragment() {\n\tvec3 c = texture(screen, SCREEN_UV).rgb;\n\tfloat l = dot(c, vec3(0.3, 0.59, 0.11));\n\tCOLOR = vec4(0.1, l * 1.4, 0.15, 1.0);\n}"
}
```

The built-in shaders are in `game/shaders/voxel/` and are a good starting point.
