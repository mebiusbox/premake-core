--
-- xcode_pbxproj.lua
-- Generate an Xcode project, which incorporates the entire Premake structure.
-- Copyright (c) 2009 Jason Perkins and the Premake project
--

	local xcode = premake.xcode
	local tree  = premake.tree


--
-- Preprocess the project information, building a project tree and associating Xcode
-- specific metadata with projects, files, and targets.
--
-- @param sln
--    The solution being generated.
-- @returns
--    A context object with these properties:
--    root    - a tree containing the solution, projects, and all files with metadata.
--    targets - a list of binary targets with metadata
--

	function xcode.buildcontext(sln)
		local ctx = { }
		
		-- create the project tree
		ctx.root = tree.new(sln.name)
		ctx.root.id = xcode.newid()

		-- localized files need an extra ID (see below)
		ctx.variantgroups = { }
		
		for prj in premake.eachproject(sln) do
			-- build the project tree and add it to the solution
			local prjnode = premake.project.buildsourcetree(prj)
			tree.insert(ctx.root, prjnode)
			
			tree.traverse(prjnode, {
				-- assign IDs to all nodes in the tree
				onnode = function(node)
					node.id = xcode.newid()
				end,
				
				onleaf = function(node)
					-- Premake is setup for the idea of a solution file referencing multiple project files,
					-- but Xcode uses a single file for everything. Convert the file paths from project
					-- location relative to solution (the one Xcode file) location relative to compensate.
					if node.path then
						node.path = xcode.rebase(prj, node.path)
					end
					
					-- assign a build ID to buildable files
					local category = xcode.getfilecategory(node.name)
					if category then
						node.buildid = xcode.newid()
					end
					
					-- localized files are stored in "variant groups". The file, such as 'MainMenu.xib',
					-- only appears once in the project tree with each language listed underneath it.
					-- (this is the reverse of how it actually appears on the filesystem). This file
					-- has an extra ID to represent this group, in addition to its file ID.
					if xcode.islocalized(node) then
						if not ctx.variantgroups[node.name] then
							ctx.variantgroups[node.name] = { id = xcode.newid() }
						end
						table.insert(ctx.variantgroups[node.name], node)
					end
				end
			}, true)
		end

		
		-- Targets live outside the main source tree. In general there is one target per Premake
		-- project; projects with multiple kinds require multiple targets, one for each kind
		ctx.targets = { }
		for _, prjnode in ipairs(ctx.root.children) do
			-- keep track of which kinds have already been created
			local kinds = { }
			for cfg in premake.eachconfig(prjnode.project) do
				if not table.contains(kinds, cfg.kind) then					
					-- create a new target
					table.insert(ctx.targets, {
						prjnode = prjnode,
						kind = cfg.kind,
						name = prjnode.project.name .. path.getextension(cfg.buildtarget.name),
						id = xcode.newid(),
						fileid = xcode.newid(),
						sourcesid = xcode.newid(),
						frameworksid = xcode.newid()
					})

					-- mark this kind as done
					table.insert(kinds, cfg.kind)
				end
			end
		end
		
		-- Create IDs for configuration section and configuration blocks for each
		-- target, as well as a root level configuration
		local function assigncfgs(n)
			n.cfgsectionid = xcode.newid()
			n.cfgids = { }
			for _, cfgname in ipairs(sln.configurations) do
				n.cfgids[cfgname] = xcode.newid()
			end
		end
		assigncfgs(ctx.root)
		for _, target in ipairs(ctx.targets) do
			assigncfgs(target)
		end

		return ctx
	end


--
-- Return the Xcode category (for lack of a better term) for a file, such 
-- as "Sources" or "Resources".
--
-- @param fname
--    The file name to identify.
-- @returns
--    An Xcode file category, string.
--

	function xcode.getfilecategory(fname)
		print("Category for ", fname)
		local categories = {
			[".c"   ] = "Sources",
			[".cc"  ] = "Sources",
			[".cpp" ] = "Sources",
			[".cxx" ] = "Sources",
			[".m"   ] = "Sources",
			[".xib" ] = "Resources",
		}
		return categories[path.getextension(fname)]
	end


--
-- Return the Xcode type for a given file, based on the file extension.
--
-- @param fname
--    The file name to identify.
-- @returns
--    An Xcode file type, string.
--

	function xcode.getfiletype(fname)
		local types = {
			[".c"   ] = "sourcecode.c.c",
			[".cc"  ] = "sourcecode.cpp.cpp",
			[".cpp" ] = "sourcecode.cpp.cpp",
			[".css" ] = "text.css",
			[".cxx" ] = "sourcecode.cpp.cpp",
			[".gif" ] = "image.gif",
			[".h"   ] = "sourcecode.c.h",
			[".html"] = "text.html",
			[".lua" ] = "sourcecode.lua",
			[".m"   ] = "sourcecode.c.objc",
			[".xib" ] = "file.xib",
		}
		return types[path.getextension(fname)] or "text"
	end


--
-- Return the Xcode product type, based target kind.
--
-- @param kind
--    The target kind to identify.
-- @returns
--    An Xcode product type, string.
--

	function xcode.getproducttype(kind)
		local types = {
			ConsoleApp = "com.apple.product-type.tool",
		}
		return types[kind]
	end


--
-- Return the Xcode target type, based on the target file extension.
--
-- @param kind
--    The target kind to identify.
-- @returns
--    An Xcode target type, string.
--

	function xcode.gettargettype(kind)
		local types = {
			ConsoleApp = "compiled.mach-o.executable",
		}
		return types[kind]
	end


--
-- Returns true if a node represents a localized file.
--
--

	function xcode.islocalized(node)
		if xcode.getfilecategory(node.name) ~= "Resources" then
			return false
		end
		if not node.parent.path then
			return false
		end
		if path.getextension(node.parent.path) ~= ".lproj" then
			return false
		end
		return true
	end


--
-- Retrieves a unique 12 byte ID for an object.
--
-- @returns
--    A 24-character string representing the 12 byte ID.
--

	function xcode.newid()
		return string.format("%04X%04X%04X%012d", math.random(0, 32767), math.random(0, 32767), math.random(0, 32767), os.time())
	end


--
-- Converts a path or list of paths from project-relative to solution-relative.
--
-- @param prj
--    The project containing the path.
-- @param p
--    A path or list of paths.
-- @returns
--    The rebased path or paths.
--

	function xcode.rebase(prj, p)
		if not p then
			test.print(debug.traceback())
		end
		if type(p) == "string" then
			return path.getrelative(prj.solution.location, path.join(prj.location, p))
		else
			local result = { }
			for i, v in ipairs(p) do
				result[i] = xcode.rebase(p[i])
			end
			return result
		end
	end


--
-- BEGIN SECTION GENERATORS
--

	function xcode.header()
		_p('// !$*UTF8*$!')
		_p('{')
		_p('\tarchiveVersion = 1;')
		_p('\tclasses = {')
		_p('\t};')
		_p('\tobjectVersion = 45;')
		_p('\tobjects = {')
		_p('')
	end


	function xcode.PBXBuildFile(ctx)
		local resources = { }
		_p('/* Begin PBXBuildFile section */')
		tree.traverse(ctx.root, {
			onleaf = function(node)
				if node.buildid then
					local id = node.id
					
					-- localized resources are only listed once, add use their variant group ID 
					-- rather than a file ID, so all languages are referenced at once.
					if xcode.islocalized(node) then
						if resources[node.name] then return end
						id = ctx.variantgroups[node.name].id
						resources[node.name] = true
					end
			
					_p('\t\t%s /* %s in %s */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };', 
						node.buildid, node.name, xcode.getfilecategory(node.name), id, node.name)
				end
			end
		})
		_p('/* End PBXBuildFile section */')
		_p('')
	end

	
	function xcode.PBXFileReference(ctx)
		_p('/* Begin PBXFileReference section */')
		tree.traverse(ctx.root, {
			onleaf = function(node)
				-- is this a project with no files?
				if not node.path then return end

				local nodename, nodepath, encoding
				if xcode.getfilecategory(node.name) == "Resources" then
					if path.getextension(node.parent.name) == ".lproj" then
						nodename = path.getbasename(node.parent.name)
						nodepath = path.join(tree.getlocalpath(node.parent), node.name)
					end
				else
					encoding = " fileEncoding = 4;"
				end
				
				nodename = nodename or node.name
				nodepath = nodepath or tree.getlocalpath(node)
				encoding = encoding or ""

				_p('\t\t%s /* %s */ = {isa = PBXFileReference;%s lastKnownFileType = %s; name = %s; path = %s; sourceTree = "<group>"; };',
					node.id, nodename, encoding, xcode.getfiletype(node.name), nodename, nodepath)
			end
		})
		for _, target in ipairs(ctx.targets) do
			_p('\t\t%s /* %s */ = {isa = PBXFileReference; explicitFileType = "%s"; includeInIndex = 0; path = %s; sourceTree = BUILT_PRODUCTS_DIR; };',
				target.fileid, target.name, xcode.gettargettype(target.kind), target.name)
		end
		_p('/* End PBXFileReference section */')
		_p('')
	end
	
	
	function xcode.PBXVariantGroup(ctx)
		_p('/* Begin PBXVariantGroup section */')
		for name, group in pairs(ctx.variantgroups) do
			_p('\t\t%s /* %s */ = {', group.id, name)
			_p('\t\t\tisa = PBXVariantGroup;')
			_p('\t\t\tchildren = (')
			for _, node in ipairs(group) do
				_p('\t\t\t\t%s /* %s */,', node.id, path.getbasename(node.parent.name))
			end
			_p('\t\t\t);')
			_p('\t\t\tname = %s;', name)
			_p('\t\t\tsourceTree = "<group>";')
			_p('\t\t};')
		end
		_p('/* End PBXVariantGroup section */')
		_p('')
	end


	function xcode.footer()
		_p('\t};')
		_p('\trootObject = 08FB7793FE84155DC02AAC07 /* Project object */;')
		_p('}')
	end


--
-- Generate the project.pbxproj file.
--
-- @param sln
--    The target solution.
--

	function premake.xcode.pbxproj(sln)

		-- Build a project tree and target list, with Xcode specific metadata attached
		local ctx = xcode.buildcontext(sln)

		-- If this solution has only a single project, use that project as the root
		-- of the source tree to avoid the otherwise empty solution node. If there are
		-- multiple projects, keep the solution node as the root so each project can
		-- have its own top-level group for its files.
		local prjroot = iif(#ctx.root.children == 1, ctx.root.children[1], ctx.root)


		-- Begin file generation --
		xcode.header()
		xcode.PBXBuildFile(ctx)
		xcode.PBXFileReference(ctx)

		_p('/* Begin PBXFrameworksBuildPhase section */')
		for _, target in ipairs(ctx.targets) do
			_p('\t\t%s /* Frameworks */ = {', target.frameworksid)
			_p('\t\t\tisa = PBXFrameworksBuildPhase;')
			_p('\t\t\tbuildActionMask = 2147483647;')
			_p('\t\t\tfiles = (')
			_p('\t\t\t);')
			_p('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
			_p('\t\t};')
		end
		_p('/* End PBXFrameworksBuildPhase section */')
		_p('')
		

		_p('/* Begin PBXGroup section */')
		tree.traverse(prjroot, {
			onbranch = function(node, depth)
				_p('\t\t%s /* %s */ = {', node.id, node.name)
				_p('\t\t\tisa = PBXGroup;')
				_p('\t\t\tchildren = (')
				for _, child in ipairs(node.children) do
					_p('\t\t\t\t%s /* %s */,', child.id, child.name)
				end
				_p('\t\t\t);')
				_p('\t\t\tname = %s;', node.name)
				if node.path then
					_p('\t\t\tpath = %s;', iif(node.parent.path, node.name, node.path))
				end
				_p('\t\t\tsourceTree = "<group>";')
				_p('\t\t};')
			end
		}, true)
		_p('/* End PBXGroup section */')
		_p('')

		
		_p('/* Begin PBXNativeTarget section */')
		for _, target in ipairs(ctx.targets) do
			_p('\t\t%s /* %s */ = {', target.id, target.name)
			_p('\t\t\tisa = PBXNativeTarget;')
			_p('\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "%s" */;', target.cfgsectionid, target.name)
			_p('\t\t\tbuildPhases = (')
			_p('\t\t\t\t%s /* Sources */,', target.sourcesid)
			_p('\t\t\t\t%s /* Frameworks */,', target.frameworksid)
			_p('\t\t\t);')
			_p('\t\t\tbuildRules = (')
			_p('\t\t\t);')
			_p('\t\t\tdependencies = (')
			_p('\t\t\t);')
			_p('\t\t\tname = %s;', target.name)
			_p('\t\t\tproductName = %s;', target.name)
			_p('\t\t\tproductReference = %s /* %s */;', target.fileid, target.name)
			_p('\t\t\tproductType = "%s";', xcode.getproducttype(target.kind))
			_p('\t\t};')
		end
		_p('/* End PBXProject section */')
		_p('')


		_p('/* Begin PBXProject section */')
		_p('\t\t08FB7793FE84155DC02AAC07 /* Project object */ = {')
		_p('\t\t\tisa = PBXProject;')
		_p('\t\t\tbuildConfigurationList = 1DEB928908733DD80010E9CD /* Build configuration list for PBXProject "%s" */;', prjroot.name)
		_p('\t\t\tcompatibilityVersion = "Xcode 3.1";')
		_p('\t\t\thasScannedForEncodings = 1;')
		_p('\t\t\tmainGroup = %s /* %s */;', prjroot.id, prjroot.name)
		_p('\t\t\tprojectDirPath = "";')
		_p('\t\t\tprojectRoot = "";')
		_p('\t\t\ttargets = (')
		for _, target in ipairs(ctx.targets) do
			_p('\t\t\t\t%s /* %s */,', target.id, target.name)
		end
		_p('\t\t\t);')
		_p('\t\t};')
		_p('/* End PBXProject section */')
		_p('')


		_p('/* Begin PBXSourcesBuildPhase section */')
		for _, target in ipairs(ctx.targets) do
			_p('\t\t%s /* Sources */ = {', target.sourcesid)
			_p('\t\t\tisa = PBXSourcesBuildPhase;')
			_p('\t\t\tbuildActionMask = 2147483647;')
			_p('\t\t\tfiles = (')
			tree.traverse(target.prjnode, {
				onleaf = function(node)
					if node.buildid then
						_p('\t\t\t\t%s /* %s in Sources */,', node.buildid, node.name)
					end
				end
			})
			_p('\t\t\t);')
			_p('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
			_p('\t\t};')
		end
		_p('/* End PBXSourcesBuildPhase section */')
		_p('')

		xcode.PBXVariantGroup(ctx)
		
		_p('/* Begin XCBuildConfiguration section */')
		for _, target in ipairs(ctx.targets) do
			local prj = target.prjnode.project
			for cfg in premake.eachconfig(target.prjnode.project) do
				_p('\t\t%s /* %s */ = {', target.cfgids[cfg.name], cfg.name)
				_p('\t\t\tisa = XCBuildConfiguration;')
				_p('\t\t\tbuildSettings = {')
				_p('\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;')
				_p('\t\t\t\tCONFIGURATION_BUILD_DIR = %s;', xcode.rebase(prj, cfg.buildtarget.directory))
				if cfg.flags.Symbols then
					_p('\t\t\t\tCOPY_PHASE_STRIP = NO;')
				end
				_p('\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;')
				if cfg.flags.Symbols then
					_p('\t\t\t\tGCC_ENABLE_FIX_AND_CONTINUE = YES;')
				end
				_p('\t\t\t\tGCC_MODEL_TUNING = G5;')
				if #cfg.defines > 0 then
					_p('\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (')
					_p(table.implode(cfg.defines, "\t\t\t\t", ",\n"))
					_p('\t\t\t\t);')
				end
				_p('\t\t\t\tPRODUCT_NAME = %s;', cfg.buildtarget.name)
				_p('\t\t\t\tSYMROOT = %s;', xcode.rebase(prj, cfg.objectsdir))
				_p('\t\t\t};')
				_p('\t\t\tname = %s;', cfg.name)
				_p('\t\t};')
			end
		end
		for _, cfgname in ipairs(sln.configurations) do
			_p('\t\t%s /* %s */ = {', ctx.root.cfgids[cfgname], cfgname)
			_p('\t\t\tisa = XCBuildConfiguration;')
			_p('\t\t\tbuildSettings = {')
			_p('\t\t\t\tARCHS = "$(ARCHS_STANDARD_32_BIT)";')
			_p('\t\t\t\tGCC_C_LANGUAGE_STANDARD = c99;')
			_p('\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES;')
			_p('\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;')
			_p('\t\t\t\tONLY_ACTIVE_ARCH = YES;')
			_p('\t\t\t\tPREBINDING = NO;')
			_p('\t\t\t\tSDKROOT = macosx10.5;')

			-- I don't have any concept of a solution level objects directory so use the first project
			local prj1 = premake.getconfig(sln.projects[1])
			_p('\t\t\t\tSYMROOT = %s;', xcode.rebase(prj1, prj1.objectsdir))
			_p('\t\t\t};')
			_p('\t\t\tname = %s;', cfgname)
			_p('\t\t};')
		end
		_p('/* End XCBuildConfiguration section */')
		_p('')
		
		
		_p('/* Begin XCConfigurationList section */')
		for _, target in ipairs(ctx.targets) do
			_p('\t\t%s /* Build configuration list for PBXNativeTarget "%s" */ = {', target.cfgsectionid, target.name)
			_p('\t\t\tisa = XCConfigurationList;')
			_p('\t\t\tbuildConfigurations = (')
			for _, cfgname in ipairs(sln.configurations) do
				_p('\t\t\t\t%s /* %s */,', target.cfgids[cfgname], cfgname)
			end
			_p('\t\t\t);')
			_p('\t\t\tdefaultConfigurationIsVisible = 0;')
			_p('\t\t\tdefaultConfigurationName = %s;', sln.configurations[1])
			_p('\t\t};')
		end
		_p('\t\t1DEB928908733DD80010E9CD /* Build configuration list for PBXProject "%s" */ = {', prjroot.name)
		_p('\t\t\tisa = XCConfigurationList;')
		_p('\t\t\tbuildConfigurations = (')
		for _, cfgname in ipairs(sln.configurations) do
			_p('\t\t\t\t%s /* %s */,', ctx.root.cfgids[cfgname], cfgname)
		end
		_p('\t\t\t);')
		_p('\t\t\tdefaultConfigurationIsVisible = 0;')
		_p('\t\t\tdefaultConfigurationName = %s;', sln.configurations[1])
		_p('\t\t};')
		_p('/* End XCConfigurationList section */')

		xcode.footer()
	end