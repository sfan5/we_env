local mh = worldedit.manip_helpers

---------------------------------------------
-- manipulations
---------------------------------------------

local function fall(pos1, pos2)
	local pos1, pos2 = worldedit.sort_pos(pos1, pos2)
	local dim = vector.subtract(pos2, pos1) -- technically incorrect but cba to fix
	if dim.y == 0 then return 0 end

	local manip, area = mh.init(pos1, pos2)
	local data = manip:get_data()

	local count = 0
	local stride = {x=1, y=area.ystride, z=area.zstride}
	local offset = vector.subtract(pos1, area.MinEdge)
	local c_air = minetest.get_content_id("air")
	for x = 0, dim.x do
		local index_x = offset.x + x + 1 -- +1 for 1-based indexing
		for z = 0, dim.z do
			local index_z = index_x + (offset.z + z) * stride.z

			local y = 0
			local fall_height = 0
			while y < dim.y do
				local index = index_z + (offset.y + y) * stride.y
				local ndef = minetest.registered_nodes[minetest.get_name_from_content_id(data[index])]
				local did_fall = false
				if ndef ~= nil then
					if ndef.groups.falling_node ~= nil and fall_height > 0 then
						-- move all nodes above down by `fall_height`
						-- FIXME: move meta & param2 too
						for y2 = y, dim.y do
							local index2 = index_z + (offset.y + y2) * stride.y
							data[index2 - stride.y * fall_height] = data[index2]
							data[index2] = c_air
						end
						count = count + (dim.y - y)
						did_fall = true
					elseif not ndef.walkable then
						fall_height = fall_height + 1
					else -- walkable and won't fall
						fall_height = 0
					end
				end

				if did_fall then
					-- restart processing from node above the one that fell
					y = y - fall_height + 1
					fall_height = 0
				else
					y = y + 1
				end
			end
		end
	end

	mh.finish(manip, data)
	return count
end

local function populate(pos1, pos2)
	local pos1, pos2 = worldedit.sort_pos(pos1, pos2)
	local dim = vector.subtract(pos2, pos1) -- technically incorrect but cba to fix

	local manip, area = mh.init(pos1, pos2)
	local data = manip:get_data()

	local stride = {x=1, y=area.ystride, z=area.zstride}
	local offset = vector.subtract(pos1, area.MinEdge)

	local count = 0
	local c_air = minetest.get_content_id("air")
	local c_dirt = minetest.get_content_id("default:dirt")
	local c_grass = minetest.get_content_id("default:dirt_with_grass")
	local c_stone = minetest.get_content_id("default:stone")
	for x = 0, dim.x do
		local index_x = offset.x + x + 1 -- +1 for 1-based indexing
		for z = 0, dim.z do
			local index_z = index_x + (offset.z + z) * stride.z

			local y = dim.y
			local last_was_air = false
			local depth = 0
			while y >= 0 do
				local index = index_z + (offset.y + y) * stride.y
				if data[index] == c_dirt then
					depth = depth + 1
					if last_was_air then
						data[index] = c_grass
						count = count + 1
					elseif depth > 3 then
						data[index] = c_stone
						count = count + 1
					end
				else
					depth = 0
				end

				last_was_air = data[index] == c_air
				y = y - 1
			end
		end
	end

	mh.finish(manip, data)
	return count
end

local print2d = function(name, w, h, index) -- for debugging
	local max = 1
	for y = 0, h-1 do
	for x = 0, w-1 do
		max = math.max(max, index(x, y))
	end
	end
	max = math.ceil(max)
	local s = "##" .. name .. "\n" .. w .. "," .. h .. ":"
	for y = 0, h-1 do
	for x = 0, w-1 do
		local n = (1 - index(x, y) / max) * 255
		assert(n >= 0 and n <= 255)
		s = s .. string.format("%02x", math.floor(n))
	end
	end
	print(s)
end

local EWMA_alpha = 0.6
local WEIGHT = {orig=0.5, x=0.25, z=0.25}
local function smooth(pos1, pos2)
	local pos1, pos2 = worldedit.sort_pos(pos1, pos2)
	local dim = vector.add(vector.subtract(pos2, pos1), 1)
	if dim.x < 2 or dim.y < 2 or dim.z < 2 then return 0 end

	local manip, area = mh.init(pos1, pos2)
	local data = manip:get_data()

	local stride = {x=1, y=area.ystride, z=area.zstride}
	local offset = vector.subtract(pos1, area.MinEdge)
	local c_air = minetest.get_content_id("air")
	local c_dirt = minetest.get_content_id("default:dirt")

	-- read heightmap from data
	local heightmap = {}
	local hstride = {x=1, z=dim.x}
	for x = 0, dim.x-1 do
		for z = 0, dim.z-1 do
			heightmap[x + (z * hstride.z) + 1] = 0
		end
	end
	for x = 0, dim.x-1 do
		local index_x = offset.x + x + 1 -- +1 for 1-based indexing
		for z = 0, dim.z-1 do
			local index_z = index_x + (offset.z + z) * stride.z

			local y = dim.y-1
			while y >= 0 do
				if data[index_z + (offset.y + y) * stride.y] ~= c_air then
					heightmap[x + (z * hstride.z) + 1] = y + 1
					break
				end
				y = y - 1
			end
		end
	end

	-- calculate EWMA for each x/z slice
	local slice_x, slice_z = {}, {}
	for x = 0, dim.x-1 do -- x+
		local res = {}
		local last = heightmap[x + 1]
		res[1] = last
		for z = 1, dim.z-1 do
			local h = heightmap[x + (z * hstride.z) + 1]
			last = EWMA_alpha * h + (1 - EWMA_alpha) * last
			res[z+1] = last
		end
		slice_x[x+1] = res
	end
	for x = 0, dim.x-1 do -- x- & averaging
		local res = slice_x[x+1]
		local last = heightmap[x + (dim.z-1 * hstride.z) + 1]
		res[dim.z] = (res[dim.z] + last) / 2
		for z = dim.z-2, 0, -1 do
			local h = heightmap[x + (z * hstride.z) + 1]
			last = EWMA_alpha * h + (1 - EWMA_alpha) * last
			res[z+1] = (res[z+1] + last) / 2
		end
	end
	for z = 0, dim.z-1 do -- z+
		local res = {}
		local last = heightmap[(z * hstride.z) + 1]
		res[1] = last
		for x = 1, dim.x-1 do
			local h = heightmap[x + (z * hstride.z) + 1]
			last = EWMA_alpha * h + (1 - EWMA_alpha) * last
			res[x+1] = last
		end
		slice_z[z+1] = res
	end
	for z = 0, dim.z-1 do -- z- & averaging
		local res = slice_z[z+1]
		local last = heightmap[dim.x-1 + (z * hstride.z) + 1]
		res[dim.x] = (res[dim.x] + last) / 2
		for x = dim.x-2, 0, -1 do
			local h = heightmap[x + (z * hstride.z) + 1]
			last = EWMA_alpha * h + (1 - EWMA_alpha) * last
			res[x+1] = (res[x+1] + last) / 2
		end
	end

	--[[print2d("heightmap", dim.x, dim.z, function(x, z)
		return heightmap[x + (z * hstride.z) + 1]
	end)
	print2d("ewma_x", dim.x, dim.z, function(x, z)
		return slice_x[x+1][z+1]
	end)
	print2d("ewma_z", dim.x, dim.z, function(x, z)
		return slice_z[z+1][x+1]
	end)]]

	-- adjust actual heights based on results
	local count = 0
	for x = 0, dim.x-1 do
		local index_x = offset.x + x + 1 -- +1 for 1-based indexing
		for z = 0, dim.z-1 do
			local index_z = index_x + (offset.z + z) * stride.z

			local old_height = heightmap[x + (z * hstride.z) + 1]
			local new_height = math.floor(
				old_height * WEIGHT.orig +
				slice_x[x+1][z+1] * WEIGHT.x +
				slice_z[z+1][x+1] * WEIGHT.z
			)

			if old_height > new_height then
				-- need to delete nodes
				local y = old_height-1
				while y >= new_height do
					local index = index_z + (offset.y + y) * stride.y
					if data[index] == c_dirt then data[index] = c_air end

					count = count + 1
					y = y - 1
				end
			elseif old_height < new_height then
				-- need to add nodes
				local y = old_height
				while y <= new_height-1 do
					local index = index_z + (offset.y + y) * stride.y
					if data[index] == c_air then data[index] = c_dirt end

					count = count + 1
					y = y + 1
				end
			end
		end
	end

	mh.finish(manip, data)
	return count
end

---------------------------------------------
-- chat commands
---------------------------------------------

minetest.register_chatcommand("/fall", {
	params = "",
	description = "Apply gravity to all falling nodes in current WorldEdit region",
	privs = {worldedit=true},
	func = function(name, param)
		local pos1, pos2 = worldedit.pos1[name], worldedit.pos2[name]
		if pos1 == nil or pos2 == nil then
			worldedit.player_notify(name, "no region selected")
			return nil
		end
		local count = fall(pos1, pos2)
		worldedit.player_notify(name, count .. " nodes updated")
	end,
})

minetest.register_chatcommand("/populate", {
	params = "",
	description = "Populate dirt in current WorldEdit region",
	privs = {worldedit=true},
	func = function(name, param)
		local pos1, pos2 = worldedit.pos1[name], worldedit.pos2[name]
		if pos1 == nil or pos2 == nil then
			worldedit.player_notify(name, "no region selected")
			return nil
		end
		local count = populate(pos1, pos2)
		worldedit.player_notify(name, count .. " nodes updated")
	end,
})

minetest.register_chatcommand("/smooth", {
	params = "",
	description = "Smooth terrain (dirt) in current WorldEdit region",
	privs = {worldedit=true},
	func = function(name, param)
		local pos1, pos2 = worldedit.pos1[name], worldedit.pos2[name]
		if pos1 == nil or pos2 == nil then
			worldedit.player_notify(name, "no region selected")
			return nil
		end
		local count = smooth(pos1, pos2)
		worldedit.player_notify(name, count .. " nodes updated")
	end,
})
