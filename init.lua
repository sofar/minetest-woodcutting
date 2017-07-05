woodcutting = {}
woodcutting.tree_content_ids = {}
woodcutting.leaves_content_ids = {}
woodcutting.inprocess = {}

-----------------------------
-- Process single node async
----------------------------
local function woodcut_node(pos, playername)
	-- check digger is still in game
	local digger = minetest.get_player_by_name(playername)
	if not digger then
		woodcutting.inprocess[playername] = nil
		return
	end

	local node = minetest.get_node(pos)
	local nodedef = minetest.registered_nodes[node.name]
	-- check node already digged
	if not (nodedef.groups.tree or nodedef.groups.leaves or nodedef.groups.leafdecay) then
		return
	end
	-- dig the node
	minetest.node_dig(pos, node, digger)

	-- Search for leaves only for tree
	if not nodedef.groups.tree then
		return
	end

	-- read map around the node
	local vm = minetest.get_voxel_manip()
	local minp, maxp = vm:read_from_map(vector.subtract(pos, 8), vector.add(pos, 8))
	local area = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
	local data = vm:get_data()

	-- process leaves nodes
	for i in area:iterp(vector.subtract(pos,8), vector.add(pos,8)) do
		if woodcutting.leaves_content_ids[data[i]] then
			local leavespos = area:position(i)
			-- search if no other tree node near the leaves
			local tree_found = false
			for i2 in area:iterp(vector.subtract(leavespos,2), vector.add(leavespos,2)) do
				if woodcutting.tree_content_ids[data[i2] ] then
--					local chkposhash = minetest.hash_node_position(area:position(i2))
--					if not process.treenodes_hashed[chkposhash] and
						tree_found = true
						break
--					end
				end
			end
			if not tree_found then
				minetest.after(0.1, woodcut_node, leavespos, playername)
			end
		end
	end
end

----------------------------
-- Process all relevant nodes around the digged
----------------------------
local function woodcut(playername)
	-- check digger is still in game
	local digger = minetest.get_player_by_name(playername)
	if not digger then
		woodcutting.inprocess[playername] = nil
		return
	end
	local playerpos = digger:get_pos()

	-- check the process
	local process =  woodcutting.inprocess[playername] 
	if not process then
		return
	end

	-- sort the table for priorization higher nodes, select the first one and process them
	table.sort(process.treenodes_sorted, function(a,b)
		local aval = math.abs(playerpos.x-a.x) + math.abs(playerpos.z-a.z)
		local bval = math.abs(playerpos.x-b.x) + math.abs(playerpos.z-b.z)
		if aval == bval then -- if same horizontal distance, prever higher node
			aval = -a.z
			bval = -b.z
		end
		return aval < bval
	end)
	local pos = process.treenodes_sorted[1]
	if pos then
		local poshash = minetest.hash_node_position(pos)
		local nodedef = minetest.registered_nodes[process.treenodes_hashed[poshash]]
		local capabilities = digger:get_wielded_item():get_tool_capabilities()
		local dig_params = minetest.get_dig_params(nodedef.groups, capabilities)

		table.remove(process.treenodes_sorted, 1)
		process.treenodes_hashed[poshash] = nil
		minetest.after(0.0, woodcut_node, pos, playername)

		-- next step
		minetest.after(dig_params.time, woodcut, playername)
	else
		-- finished
		woodcutting.inprocess[playername] = nil
	end
end

----------------------------
-- dig node - check if woodcutting and initialize the work
----------------------------
minetest.register_on_dignode(function(pos, oldnode, digger)
	local removed_nodedef = minetest.registered_nodes[oldnode.name]

	-- check removed node is tree / check the digger is still online
	if not removed_nodedef
			or not removed_nodedef.groups.tree
			or not digger then
		return
	end

	-- Check if it is an in process job
	local playername = digger:get_player_name()
	local sneak = digger:get_player_control().sneak
	local process
	if woodcutting.inprocess[playername] then
		-- woodcutting job already in process
		process = woodcutting.inprocess[playername]
	elseif not sneak then
		-- No job, no sneak, nothing to do
		return
	else
		-- No job but sneak pressed - start new process
		process = {
			sneak_pressed = true,
			treenodes_sorted = {}, -- simple sortable list
			treenodes_hashed = {}, -- With minetest.hash_node_position(9 as key for deduplication
		}
		woodcutting.inprocess[playername] = process
		minetest.after(0.1, woodcut, playername) -- note: woodcut is called after the treenodes_lists are filled
	end

	-- process the sneak toggle
	if sneak then
		if not process.sneak_pressed then
			-- sneak pressed second time - stop the work
			woodcutting.inprocess[playername] = nil
			return
		end
	else
		if process.sneak_pressed then
			process.sneak_pressed = false
		end
	end

	-- read map around the node
	local vm = minetest.get_voxel_manip()
	local minp, maxp = vm:read_from_map(vector.subtract(pos, 1), vector.add(pos, 1))
	local area = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
	local data = vm:get_data()

	-- collect tree nodes to the lists
	for i in area:iterp(vector.subtract(pos,1), vector.add(pos,1)) do
		local tree_nodename = woodcutting.tree_content_ids[data[i]]
		if tree_nodename then
			local pos = area:position(i)
			local poshash = minetest.hash_node_position(pos)
			if not process.treenodes_hashed[poshash] then
				table.insert(process.treenodes_sorted, pos)
				process.treenodes_hashed[poshash] = tree_nodename
			end
		end
	end
end)


-- start collecting infos about trees and leaves after all mods loaded
minetest.after(0, function ()
	for k, v in pairs(minetest.registered_nodes) do
		if v.groups.tree then
			local id = minetest.get_content_id(k)
			woodcutting.tree_content_ids[id] = k
		elseif v.groups.leaves or v.groups.leafdecay then
			local id = minetest.get_content_id(k)
			woodcutting.leaves_content_ids[id] = k
		end
	end
end)
