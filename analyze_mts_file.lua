
handle_schematics = {}

-- taken from https://github.com/MirceaKitsune/minetest_mods_structures/blob/master/structures_io.lua (Taokis Sructures I/O mod)
-- gets the size of a structure file
-- nodenames: contains all the node names that are used in the schematic
-- on_constr: lists all the node names for which on_construct has to be called after placement of the schematic
handle_schematics.analyze_mts_file = function( path )
	local size = { x = 0, y = 0, z = 0, version = 0 }
	local version = 0;

	local file = io.open(path..'.mts', "r")
	if (file == nil) then
		return nil
	end
--print('[mg_villages] Analyzing .mts file '..tostring( path..'.mts' ));
--if( not( string.byte )) then
--	print( '[mg_villages] Error: string.byte undefined.');
--	return nil;
--end

	-- thanks to sfan5 for this advanced code that reads the size from schematic files
	local read_s16 = function(fi)
		return string.byte(fi:read(1)) * 256 + string.byte(fi:read(1))
	end

	local function get_schematic_size(f)
		-- make sure those are the first 4 characters, otherwise this might be a corrupt file
		if f:read(4) ~= "MTSM" then
			return nil
		end
		-- advance 2 more characters
		local version = read_s16(f); --f:read(2)
		-- the next characters here are our size, read them
		return read_s16(f), read_s16(f), read_s16(f), version
	end

	size.x, size.y, size.z, size.version = get_schematic_size(file)
	
	-- read the slice probability for each y value that was introduced in version 3
	if( size.version >= 3 ) then
		-- the probability is not very intresting for buildings so we just skip it
		file:read( size.y );
	end


	-- this list is not yet used for anything
	local nodenames = {};
	-- this list is needed for calling on_construct after place_schematic
	local on_constr = {};
	-- nodes that require after_place_node to be called
	local after_place_node = {};

	-- after that: read_s16 (2 bytes) to find out how many diffrent nodenames (node_name_count) are present in the file
	local node_name_count = read_s16( file );

	for i = 1, node_name_count do

		-- the length of the next name
		local name_length = read_s16( file );
		-- the text of the next name
		local name_text   = file:read( name_length );

		table.insert( nodenames, name_text );
		-- in order to get this information, the node has to be defined and loaded
		if( minetest.registered_nodes[ name_text ] and minetest.registered_nodes[ name_text ].on_construct) then
			table.insert( on_constr, name_text );
		end
		-- some nodes need after_place_node to be called for initialization
		if( minetest.registered_nodes[ name_text ] and minetest.registered_nodes[ name_text ].after_place_node) then
			table.insert( after_place_node, name_text );
		end
	end

	local rotated = 0;
	local burried = 0;
	local parts = path:split('_');
	if( parts and #parts > 2 ) then
		if( parts[#parts]=="0" or parts[#parts]=="90" or parts[#parts]=="180" or parts[#parts]=="270" ) then
			rotated = tonumber( parts[#parts] );
			burried = tonumber( parts[ #parts-1 ] );
			if( not( burried ) or burried>20 or burried<0) then
				burried = 0;
			end
		end
	end

	-- decompression was recently added; if it is not yet present, we need to use normal place_schematic
	if( false and not( minetest.decompress )) then
		file.close(file);
		return { size = { x=size.x, y=size.y, z=size.z}, nodenames = nodenames, on_constr = on_constr, after_place_node = after_place_node, rotated=rotated, burried=burried, scm_data_cache = nil };
	end

	local compressed_data = file:read( "*all" );
	local data_string = minetest.decompress(compressed_data, "deflate" );
	file.close(file)

	local c_ignore = minetest.get_content_id( 'ignore' );

	local ids = {};
	local needs_on_constr = {};
	-- translate nodenames to ids
	for i,v in ipairs( nodenames ) do
		ids[ i ] = minetest.get_content_id( v );
		needs_on_constr[ i ] = false;
		if( minetest.registered_nodes[ v ] and minetest.registered_nodes[ v ].on_construct ) then
			needs_on_constr[ i ] = true;
		end
	end

	local p2offset = (size.x*size.y*size.z)*3;
	local i = 1;
	local scm = {};
	for z = 1, size.z do
	for y = 1, size.y do
	for x = 1, size.x do
		if( not( scm[y] )) then
			scm[y] = {};
		end
		if( not( scm[y][x] )) then
			scm[y][x] = {};
		end
		local id = string.byte( data_string, i ) * 256 + string.byte( data_string, i+1 );
		i = i + 2;
		local p2 = string.byte( data_string, p2offset + math.floor(i/2));
		id = id+1;

		-- unkown node
		local regnode = minetest.registered_nodes[ nodenames[ id ]];
		local paramtype2 = minetest.registered_nodes[ nodenames[ id ]] and minetest.registered_nodes[ nodenames[ id ]].paramtype2
		if(     not( regnode ) and not( nodenames[ id ] )) then
			scm[y][x][z] = c_ignore;
		elseif( not( regnode )) then
			scm[y][x][z] = { node = {
					content    = c_ignore,
					name       = nodenames[ id ],
					param2     = p2} };
		elseif( paramtype2 ~= 'facedir' and paramtype2 ~= 'wallmounted' ) then
			scm[y][x][z] = ids[ id ];
		else
			scm[y][x][z] = { node = {
					content    = ids[ id ],
					--name       = nodenames[ id ],
					--param2     = p2,
                                        --rotation   = paramtype2}
					param2list = mg_villages.get_param2_rotated( paramtype2, p2 )} };
		end
	end
	end
	end

	return { size = { x=size.x, y=size.y, z=size.z}, nodenames = nodenames, on_constr = on_constr, after_place_node = after_place_node, rotated=rotated, burried=burried, scm_data_cache = scm };
end

