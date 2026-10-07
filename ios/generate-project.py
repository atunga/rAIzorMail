#!/usr/bin/env python3
"""Generate a dependency-free Xcode app project. Does not access credentials."""
from pathlib import Path
import hashlib, json
root = Path(__file__).resolve().parent
objects = {}
def uid(key): return hashlib.sha256(key.encode()).hexdigest()[:24].upper()
def obj(key, **value):
    identifier = uid(key); objects[identifier] = value; return identifier
files = sorted(root.glob('rAIzorMail/*.swift')) + sorted(root.glob('MailCore/Sources/MailCore/*.swift'))
refs, builds = [], []
for file in files:
    rel = str(file.relative_to(root))
    ref = obj(rel, isa='PBXFileReference', lastKnownFileType='sourcecode.swift', path=rel, sourceTree='SOURCE_ROOT')
    refs.append(ref); builds.append(obj(rel+':build', isa='PBXBuildFile', fileRef=ref))
resources = []
for name, kind in [('rAIzorMail/Assets.xcassets', 'folder.assetcatalog'), ('rAIzorMail/PrivacyInfo.xcprivacy', 'text.xml')]:
    ref = obj(name, isa='PBXFileReference', lastKnownFileType=kind, path=name, sourceTree='SOURCE_ROOT'); refs.append(ref)
    resources.append(obj(name+':build', isa='PBXBuildFile', fileRef=ref))
config = obj('config', isa='PBXFileReference', lastKnownFileType='text.xcconfig', path='Configuration/Build.xcconfig', sourceTree='SOURCE_ROOT'); refs.append(config)
info = obj('info', isa='PBXFileReference', lastKnownFileType='text.plist.xml', path='rAIzorMail/Info.plist', sourceTree='SOURCE_ROOT'); refs.append(info)
product = obj('product', isa='PBXFileReference', explicitFileType='wrapper.application', path='rAIzorMail.app', sourceTree='BUILT_PRODUCTS_DIR')
products = obj('products', isa='PBXGroup', children=[product], name='Products', sourceTree='<group>')
group = obj('group', isa='PBXGroup', children=refs+[products], sourceTree='<group>')
sources = obj('sources', isa='PBXSourcesBuildPhase', buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)
resource_phase = obj('resources', isa='PBXResourcesBuildPhase', buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0)
frameworks = obj('frameworks', isa='PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
project_configs, target_configs = [], []
for mode in ['Debug','Release']:
    project_configs.append(obj('project:'+mode, isa='XCBuildConfiguration', name=mode, buildSettings={'CLANG_ENABLE_MODULES':'YES', 'SDKROOT':'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET':'17.0', 'SWIFT_VERSION':'5.0', 'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O', 'DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if mode=='Debug' else ''}))
    target_configs.append(obj('target:'+mode, isa='XCBuildConfiguration', baseConfigurationReference=config, name=mode, buildSettings={'PRODUCT_NAME':'rAIzorMail', 'INFOPLIST_FILE':'rAIzorMail/Info.plist', 'GENERATE_INFOPLIST_FILE':'NO', 'CODE_SIGN_STYLE':'Automatic', 'CURRENT_PROJECT_VERSION':'1', 'MARKETING_VERSION':'0.1.0', 'TARGETED_DEVICE_FAMILY':'1,2', 'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator', 'SUPPORTS_MACCATALYST':'NO', 'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon', 'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks']}))
pc = obj('projectconfigs', isa='XCConfigurationList', buildConfigurations=project_configs, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')
tc = obj('targetconfigs', isa='XCConfigurationList', buildConfigurations=target_configs, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')
target = obj('target', isa='PBXNativeTarget', name='rAIzorMail', productName='rAIzorMail', productType='com.apple.product-type.application', productReference=product, buildConfigurationList=tc, buildPhases=[sources,frameworks,resource_phase], buildRules=[], dependencies=[])
project = obj('project', isa='PBXProject', attributes={'LastUpgradeCheck':'1600', 'BuildIndependentTargetsInParallel':'YES'}, buildConfigurationList=pc, compatibilityVersion='Xcode 14.0', developmentRegion='en', hasScannedForEncodings=0, knownRegions=['en','Base'], mainGroup=group, productRefGroup=products, projectDirPath='', projectRoot='', targets=[target])
def encode(value, indent=0):
    if isinstance(value, dict): return '{\n' + ''.join('  '*(indent+1)+json.dumps(str(k))+' = '+encode(v,indent+1)+';\n' for k,v in value.items()) + '  '*indent+'}'
    if isinstance(value, list): return '(' + ', '.join(encode(v,indent) for v in value) + ')'
    if isinstance(value, int): return str(value)
    return json.dumps(value)
folder = root/'rAIzorMail.xcodeproj'; folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n')
schemes = folder/'xcshareddata'/'xcschemes'; schemes.mkdir(parents=True, exist_ok=True)
ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="rAIzorMail.app" BlueprintName="rAIzorMail" ReferencedContainer="container:rAIzorMail.xcodeproj"/>'
(schemes/'rAIzorMail.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(folder)
