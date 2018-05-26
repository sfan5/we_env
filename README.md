we_env
======

Tools to aid the forming of "natural" terrain by hand using [WorldEdit](https://github.com/Uberi/Minetest-WorldEdit)'s brush.

This is more of a proof of concept and might be merged into WorldEdit in the future.

![](https://i.imgur.com/O7PodOm.jpg)

## Command reference

* `//fall`

Make all gravity-affected nodes in the current selection fall down.
Unlike the usual "punch to cause fall" this works en masse.

* `//populate`

Convert terrain (`default:dirt` only) in current selection to look like "real" terrain.
Meaning: Add grass on top and change deeper nodes to stone.

* `//ores [y]`

Let the map generator generate ores in the selected region, this works with whatever ores mods have registered.
The optional argument specifies which height is used for deciding the ores to generate and defaults to sea level (0).

* `//smooth [<iterations>]`

Smooth terrain in the current selection. When adding nodes, the type of the top-most node in the column is used.
This uses an exponentially weighted moving average (EWMA) and should be ran with 1 or 2 iteration to produce good results. Defaults to 1 iteration.

* `//smoothbrush`

Assign terrain smoothing (see above) to a brush.
Note that the brush will smooth a 10x10 area with heights up to 48 at once.
