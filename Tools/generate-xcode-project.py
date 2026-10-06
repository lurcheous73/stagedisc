#!/usr/bin/env python3
"""Generate native macOS targets; SwiftPM remains available for CLI/tests."""
import hashlib
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
project = root / 'StageDisc.xcodeproj'
project.mkdir(exist_ok=True)
objects = []
def ident(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def quote(value): return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
def obj(name, body):
    key = ident(name); objects.append(f'{key} = {{ {body} }};'); return key
def ids(items): return '(' + ','.join(items) + ',)' if items else '()'
def sources(folder):
    refs, builds = [], []
    for file in sorted((root / folder).glob('*.swift')):
        ref = obj(folder + '/' + file.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(file.name)}; sourceTree = "<group>";')
        refs.append(ref); builds.append(obj('build ' + folder + '/' + file.name, f'isa = PBXBuildFile; fileRef = {ref};'))
    group = obj(folder, f'isa = PBXGroup; children = {ids(refs)}; path = {quote(folder)}; sourceTree = "<group>";')
    phase = obj(folder + ' phase', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {ids(builds)}; runOnlyForDeploymentPostprocessing = 0;')
    return group, phase
app_group, app_sources = sources('Sources/StageDisc')
core_group, core_sources = sources('Sources/StageDiscCore')
app_ref = obj('app', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = StageDisc.app; sourceTree = BUILT_PRODUCTS_DIR;')
core_ref = obj('core product', 'isa = PBXFileReference; explicitFileType = wrapper.framework; path = StageDiscCore.framework; sourceTree = BUILT_PRODUCTS_DIR;')
resource_ref = obj('resources', 'isa = PBXFileReference; lastKnownFileType = folder; path = Resources; sourceTree = "<group>";')
assets_ref = obj('assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = AppIcon.xcassets; sourceTree = "<group>";')
resource_refs=[]
resource_builds=[obj('build assets', f'isa = PBXBuildFile; fileRef = {assets_ref};')]
for entry in sorted((root/'Resources').iterdir()):
    kind='folder' if entry.is_dir() else 'text' if entry.suffix in ['.txt','.md'] else 'file'
    ref=obj('resource '+entry.name, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(entry.name)}; sourceTree = "<group>";')
    resource_refs.append(ref); resource_builds.append(obj('resource build '+entry.name, f'isa = PBXBuildFile; fileRef = {ref};'))
resource_group=obj('resource group', f'isa = PBXGroup; children = {ids(resource_refs)}; path = Resources; sourceTree = "<group>";')
products = obj('products', f'isa = PBXGroup; children = {ids([app_ref,core_ref])}; name = Products; sourceTree = "<group>";')
group = obj('group', f'isa = PBXGroup; children = {ids([app_group,core_group,resource_group,assets_ref,products])}; sourceTree = "<group>";')
core_link = obj('core link', f'isa = PBXBuildFile; fileRef = {core_ref};')
core_embed = obj('core embed', f'isa = PBXBuildFile; fileRef = {core_ref}; settings = {{ ATTRIBUTES = (CodeSignOnCopy,RemoveHeadersOnCopy); }};')
frameworks = obj('frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {ids([core_link])}; runOnlyForDeploymentPostprocessing = 0;')
embed = obj('embed', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 10; files = {ids([core_embed])}; name = "Embed Frameworks"; runOnlyForDeploymentPostprocessing = 0;')
resources = obj('resource phase', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {ids(resource_builds)}; runOnlyForDeploymentPostprocessing = 0;')
signing = obj('sign helpers', 'isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); inputPaths = (); outputPaths = (); name = "Sign embedded tools"; runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/bash; shellScript = ' + quote('bash "$SRCROOT/Tools/sign-helpers.sh"\n') + '; alwaysOutOfDate = 1;')
common = {'SDKROOT':'macosx','MACOSX_DEPLOYMENT_TARGET':'14.0','ARCHS':'arm64','SWIFT_VERSION':'5.0','MARKETING_VERSION':'1.0','CURRENT_PROJECT_VERSION':'3','CODE_SIGN_STYLE':'Automatic','DEVELOPMENT_TEAM':'','ENABLE_USER_SCRIPT_SANDBOXING':'NO','SWIFT_STRICT_CONCURRENCY':'minimal'}
def configs(target):
    result=[]
    for name in ['Debug','Release']:
        settings=dict(common)
        settings.update(PRODUCT_NAME=target, CODE_SIGN_IDENTITY='-' if name == 'Debug' else 'Apple Development', DEBUG_INFORMATION_FORMAT='dwarf' if name == 'Debug' else 'dwarf-with-dsym', SWIFT_OPTIMIZATION_LEVEL='-Onone' if name == 'Debug' else '-O')
        if target == 'StageDisc':
            settings.update(PRODUCT_BUNDLE_IDENTIFIER='uk.brimstonecottage.stagedisc',INFOPLIST_FILE='Tools/Xcode-Info.plist',GENERATE_INFOPLIST_FILE='NO',ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon',LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/../Frameworks',SKIP_INSTALL='NO',STAGEDISC_DISTRIBUTION='local' if name == 'Debug' else 'app-store')
            if name == 'Release': settings.update(CODE_SIGN_ENTITLEMENTS='Tools/StageDisc.entitlements',ENABLE_APP_SANDBOX='YES',ENABLE_HARDENED_RUNTIME='YES')
        else:
            settings.update(PRODUCT_BUNDLE_IDENTIFIER='uk.brimstonecottage.stagedisc.core',GENERATE_INFOPLIST_FILE='YES',DEFINES_MODULE='YES',SKIP_INSTALL='YES',INSTALL_PATH='$(LOCAL_LIBRARY_DIR)/Frameworks',DYLIB_INSTALL_NAME_BASE='@rpath')
        text=' '.join(f'{k} = {quote(v)};' for k,v in settings.items())
        result.append(obj(target+' '+name, f'isa = XCBuildConfiguration; buildSettings = {{ {text} }}; name = {name};'))
    return obj(target+' configs', f'isa = XCConfigurationList; buildConfigurations = {ids(result)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
core_configs=configs('StageDiscCore'); app_configs=configs('StageDisc')
core_target=obj('core target', f'isa = PBXNativeTarget; buildConfigurationList = {core_configs}; buildPhases = {ids([core_sources])}; buildRules = (); dependencies = (); name = StageDiscCore; productName = StageDiscCore; productReference = {core_ref}; productType = "com.apple.product-type.framework";')
proxy=obj('core proxy', f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {core_target}; remoteInfo = StageDiscCore;')
dependency=obj('core dependency', f'isa = PBXTargetDependency; target = {core_target}; targetProxy = {proxy};')
target=obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = {ids([app_sources,frameworks,resources,embed,signing])}; buildRules = (); dependencies = {ids([dependency])}; name = StageDisc; productName = StageDisc; productReference = {app_ref}; productType = "com.apple.product-type.application";')
project_configs=[obj('project '+name, f'isa = XCBuildConfiguration; buildSettings = {{ CLANG_ENABLE_MODULES = YES; }}; name = {name};') for name in ['Debug','Release']]
project_list=obj('project configs',f'isa = XCConfigurationList; buildConfigurations = {ids(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
root_obj=obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {project_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {ids([target,core_target])};')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {root_obj}; }}\n')
schemes=project/'xcshareddata/xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
(schemes/'StageDisc.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="StageDisc.app" BlueprintName="StageDisc" ReferencedContainer="container:StageDisc.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="StageDisc.app" BlueprintName="StageDisc" ReferencedContainer="container:StageDisc.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(project)
