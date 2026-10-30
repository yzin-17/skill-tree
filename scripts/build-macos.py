#!/usr/bin/env python3
"""生成原生 Xcode 工程，并使用当前本机公钥构建 .app。"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
MAC = ROOT / 'macos'
PROJECT = MAC / 'SkillAtlas.xcodeproj'

def uid(value): return hashlib.sha256(value.encode()).hexdigest()[:24].upper()
def quote(value): return json.dumps(str(value), ensure_ascii=False)

def validate_client_resources(directory):
    directory = Path(directory).resolve()
    config = json.loads((directory / 'client-config.json').read_text())
    if set(config) != {'base_url', 'certificate_sha256'}:
        raise ValueError('客户端公共配置只能包含后端地址和证书摘要。')
    address = urlsplit(config['base_url'])
    if (address.scheme != 'https' or not address.hostname or address.username is not None
            or address.password is not None or address.path not in ('', '/')
            or address.query or address.fragment):
        raise ValueError('发布后端必须是无账号、路径或参数的 HTTPS 根地址。')
    try:
        port = address.port
    except ValueError as error:
        raise ValueError('后端端口无效。') from error
    if port is not None and not 1 <= port <= 65535:
        raise ValueError('后端端口无效。')
    certificate = (directory / 'cert.der').read_bytes()
    if hashlib.sha256(certificate).hexdigest() != config['certificate_sha256']:
        raise ValueError('公共证书与客户端配置的 SHA-256 不一致。')
    subprocess.run(['openssl', 'x509', '-inform', 'DER', '-in', str(directory / 'cert.der'), '-noout'],
                   check=True, capture_output=True)
    return directory

def generate(client_resources=None):
    directory = validate_client_resources(client_resources or ROOT / '.runtime/client-resources')
    subprocess.run([sys.executable, str(ROOT / 'scripts/build-app-icon.py')], check=True)
    version = json.loads((MAC / 'version.json').read_text())
    if not re.fullmatch(r'\d+\.\d+\.\d+', version.get('version', '')) or type(version.get('build')) is not int or version['build'] < 1:
        raise ValueError('macos/version.json 的版本或构建编号无效。')
    files = sorted(p for folder in ['App', 'Core', 'Features'] for p in (MAC / folder).rglob('*.swift'))
    objects = []
    def obj(key, body):
        objects.append(f'{uid(key)} = {{ {body} }};')
        return uid(key)
    sources = []
    references = []
    resources = []
    for path in files:
        rel = str(path.relative_to(MAC))
        ref = obj(rel, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(rel)}; sourceTree = SOURCE_ROOT;')
        references.append(ref)
        sources.append(obj('build:' + rel, f'isa = PBXBuildFile; fileRef = {ref};'))
    for rel, kind in [(os.path.relpath(directory / 'cert.der', MAC), 'file'),
                      (os.path.relpath(directory / 'client-config.json', MAC), 'text.json'),
                      ('Resources/Assets.xcassets', 'folder.assetcatalog')]:
        ref = obj(rel, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(rel)}; sourceTree = SOURCE_ROOT;')
        references.append(ref)
        resources.append(obj('build:' + rel, f'isa = PBXBuildFile; fileRef = {ref};'))
    product = obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = SkillAtlas.app; sourceTree = BUILT_PRODUCTS_DIR;')
    product_group = obj('products', f'isa = PBXGroup; children = ({product}); name = Products; sourceTree = "<group>";')
    main_group = obj('main', f'isa = PBXGroup; children = ({",".join(references + [product_group])}); sourceTree = "<group>";')
    source_phase = obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(sources)}); runOnlyForDeploymentPostprocessing = 0;')
    resource_phase = obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resources)}); runOnlyForDeploymentPostprocessing = 0;')
    framework_phase = obj('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    project_configs, target_configs = [], []
    for name in ['Debug', 'Release']:
        project_configs.append(obj('project:' + name, f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 14.0; SWIFT_VERSION = 6.0; CLANG_ENABLE_MODULES = YES; }};'))
        target_configs.append(obj('target:' + name, f'''isa = XCBuildConfiguration; name = {name}; buildSettings = {{
            PRODUCT_NAME = SkillAtlas; PRODUCT_BUNDLE_IDENTIFIER = local.skillatlas.app;
            MARKETING_VERSION = {version['version']}; CURRENT_PROJECT_VERSION = {version['build']};
            GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.productivity";
            INFOPLIST_KEY_CFBundleDisplayName = "Skill Atlas";
            ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
            INFOPLIST_KEY_NSAppTransportSecurity_NSAllowsLocalNetworking = YES;
            CODE_SIGN_IDENTITY = "-"; CODE_SIGN_STYLE = Manual;
            ENABLE_APP_SANDBOX = NO; ENABLE_HARDENED_RUNTIME = YES;
            SWIFT_OPTIMIZATION_LEVEL = {quote('-Onone' if name == 'Debug' else '-O')};
            SWIFT_ACTIVE_COMPILATION_CONDITIONS = {quote('DEBUG' if name == 'Debug' else '')};
            SWIFT_EMIT_LOC_STRINGS = NO; COMBINE_HIDPI_IMAGES = YES;
        }};'''))
    pc = obj('project-configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    tc = obj('target-configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(target_configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    target = obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {tc}; buildPhases = ({source_phase},{framework_phase},{resource_phase}); buildRules = (); dependencies = (); name = SkillAtlas; productName = SkillAtlas; productReference = {product}; productType = "com.apple.product-type.application";')
    project = obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh-Hans; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base); mainGroup = {main_group}; productRefGroup = {product_group}; projectDirPath = ""; projectRoot = ""; targets = ({target});')
    PROJECT.mkdir(parents=True, exist_ok=True)
    (PROJECT / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {project}; }}\n')
    schemes = PROJECT / 'xcshareddata/xcschemes'
    schemes.mkdir(parents=True, exist_ok=True)
    ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="SkillAtlas.app" BlueprintName="SkillAtlas" ReferencedContainer="container:SkillAtlas.xcodeproj"/>'
    (schemes / 'SkillAtlas.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', action='store_true')
    parser.add_argument('--generate-only', action='store_true')
    parser.add_argument('--universal', action='store_true', help='同时构建 Apple Silicon 和 Intel 架构')
    parser.add_argument('--client-resources', type=Path, help='包含公共连接配置与 cert.der 的目录')
    parser.add_argument('--derived-data', type=Path, default=ROOT / '.runtime/DerivedData')
    args = parser.parse_args()
    if args.client_resources is None:
        # 本机入口继续读取既有配置，组装目录只包含这两个公共文件。
        import shutil
        local = ROOT / '.runtime/client-resources'
        local.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / '.runtime/client-config.json', local / 'client-config.json')
        shutil.copy2(ROOT / '.runtime/tls/cert.der', local / 'cert.der')
        args.client_resources = local
    generate(args.client_resources)
    if args.generate_only: return
    config = 'Release' if args.release else 'Debug'
    derived_data = args.derived_data.resolve()
    log = ROOT / '.runtime/logs/macos-build.log'
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('w') as output:
        command = ['xcodebuild', '-project', str(PROJECT), '-scheme', 'SkillAtlas', '-configuration', config,
                   '-derivedDataPath', str(derived_data), 'build']
        if args.universal:
            command += ['ARCHS=arm64 x86_64', 'ONLY_ACTIVE_ARCH=NO']
        result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT)
    lines = log.read_text().splitlines()
    for line in lines:
        if 'error:' in line or 'warning:' in line or '** BUILD' in line: print(line)
    print('构建日志：', log)
    if result.returncode: raise SystemExit(result.returncode)
    print('原生应用：', derived_data / f'Build/Products/{config}/SkillAtlas.app')

if __name__ == '__main__': main()
