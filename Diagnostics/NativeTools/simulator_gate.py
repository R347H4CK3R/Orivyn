#!/usr/bin/env python3
"""Strict fixture and TestAction configuration shared by explicit simulator gates."""
import argparse, json, re, xml.etree.ElementTree as ET
from pathlib import Path
from download import DEFAULT_MODEL_ID, select

GATES = {
    'reviewed-plan': ('ORIVYN_REQUIRE_PRODUCTION_REVIEWED_PLAN', 'ORIVYN_REVIEWED_PLAN_MODEL_DIR', 'JarvisEVOTests/ProductionReviewedReadPlanTests/testRequiredModelProposalApprovalAndGroundedRead', 1200, 1200),
    'native-tools': ('ORIVYN_REQUIRE_PRODUCTION_NATIVE_TOOLS', 'ORIVYN_NATIVE_TOOLS_MODEL_DIR', 'JarvisEVOTests/ProductionNativeToolsRuntimeTests/testRequiredProductionSuggestionAndReload', 300, 600),
    'local-agent': ('ORIVYN_REQUIRE_PRODUCTION_LOCAL_AGENT', 'ORIVYN_LOCAL_AGENT_MODEL_DIR', 'JarvisEVOTests/ProductionLocalAgentSessionTests/testRequiredSearchThenReadGroundedAnswer', 840, 840),
}

def prepare(scheme, models, destination, model_id=DEFAULT_MODEL_ID, gate='native-tools'):
    model = select(model_id)
    if gate not in GATES: raise ValueError('Unknown production gate')
    if not re.fullmatch(r'platform=iOS Simulator,id=[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', destination):
        raise ValueError('Exactly one explicit simulator UUID is required')
    root = Path(models); fixture = root / model['fileName']
    if not root.is_absolute() or root == Path('/') or root.is_symlink() or not root.is_dir() or fixture.is_symlink() or not fixture.is_file():
        raise ValueError('Required regular pinned model fixture is missing')
    if fixture.stat().st_size != model['byteCount']: raise ValueError('Pinned model fixture size mismatch')
    # The downloader and production LocalModelStore perform complete SHA verification;
    # the runner does not replace that production check with a cache or test stub.
    tree = ET.parse(scheme); action = tree.getroot().find('TestAction')
    if action is None: raise ValueError('Main scheme has no TestAction')
    action.set('shouldUseLaunchSchemeArgsEnv', 'NO')
    variables = action.find('EnvironmentVariables')
    if variables is None: variables = ET.SubElement(action, 'EnvironmentVariables')
    keys = {'ORIVYN_PRODUCTION_MODEL_ID'} | {key for row in GATES.values() for key in row[:2]}
    for existing in list(variables):
        if existing.get('key') in keys: variables.remove(existing)
    required, directory, selector, default, maximum = GATES[gate]
    for key, value in [(required, '1'), (directory, str(root)), ('ORIVYN_PRODUCTION_MODEL_ID', model_id)]:
        ET.SubElement(variables, 'EnvironmentVariable', key=key, value=value, isEnabled='YES')
    tree.write(scheme, encoding='UTF-8', xml_declaration=True)
    return dict(gate=gate, modelID=model_id, selector=selector, defaultAllowance=default, maximumAllowance=maximum)

if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for key in ['scheme','models','destination']: p.add_argument('--'+key,required=True)
    p.add_argument('--model-id',default=DEFAULT_MODEL_ID);p.add_argument('--gate',choices=GATES,default='native-tools')
    a=p.parse_args();print(json.dumps(prepare(a.scheme,a.models,a.destination,a.model_id,a.gate)))
