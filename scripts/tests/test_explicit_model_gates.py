import hashlib, importlib.util, json, os, pathlib, subprocess, sys, tempfile, unittest
from unittest import mock
ROOT=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'Diagnostics/NativeTools'))
import download
import simulator_gate

class ExplicitModelTests(unittest.TestCase):
    def test_catalog_exact_pins_and_default(self):
        catalog={x['id']:x for x in json.loads((ROOT/'docs/model-catalog/catalog.json').read_text())['models']}
        self.assertEqual(download.DEFAULT_MODEL_ID,'qwen3-1.7b-q8_0')
        self.assertEqual(set(download.MODELS),{'qwen3-1.7b-q8_0','qwen3-1.7b-q4_k_m'})
        for key,pin in download.MODELS.items():
            item=catalog[key]
            for field in ['fileName','sha256','byteCount']:self.assertEqual(pin[field],item[field])
            self.assertEqual(pin['downloadURL'],f"https://huggingface.co/{item['repository']}/resolve/{item['revision']}/{item['fileName']}")
        for unknown in ['', 'q4', '../model', 'qwen3-1.7b-Q8_0']:
            with self.assertRaises(ValueError):download.select(unknown)
    def test_size_and_hash_checks(self):
        with tempfile.TemporaryDirectory() as tmp:
            file=pathlib.Path(tmp)/'model';file.write_bytes(b'abc')
            pin=dict(fileName='model',byteCount=3,sha256=hashlib.sha256(b'abc').hexdigest(),downloadURL='https://example.invalid')
            with mock.patch.dict(download.MODELS,{'fixture':pin}):
                download.verify(file,'fixture')
                file.write_bytes(b'xyz')
                with self.assertRaises(ValueError):download.verify(file,'fixture')
                file.write_bytes(b'abcd')
                with self.assertRaises(ValueError):download.verify(file,'fixture')
    def test_scheme_explicit_selection_and_stale_environment_removed(self):
        import xml.etree.ElementTree as ET
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp);scheme=root/'scheme.xml';scheme.write_text('<Scheme><TestAction><EnvironmentVariables><EnvironmentVariable key="ORIVYN_REQUIRE_PRODUCTION_LOCAL_AGENT" value="1"/></EnvironmentVariables></TestAction></Scheme>')
            for model_id,pin in download.MODELS.items():
                with (root/pin['fileName']).open('wb') as f:f.truncate(pin['byteCount'])
                for gate in simulator_gate.GATES:
                    result=simulator_gate.prepare(scheme,root,'platform=iOS Simulator,id=12345678-1234-1234-1234-123456789abc',model_id,gate)
                    action=ET.parse(scheme).getroot().find('TestAction');self.assertEqual(action.get('shouldUseLaunchSchemeArgsEnv'),'NO')
                    env={x.get('key'):x.get('value') for x in action.find('EnvironmentVariables')}
                    self.assertEqual(env['ORIVYN_PRODUCTION_MODEL_ID'],model_id)
                    req,directory,selector,default,maximum=simulator_gate.GATES[gate]
                    self.assertEqual(env,{req:'1',directory:str(root),'ORIVYN_PRODUCTION_MODEL_ID':model_id})
                    self.assertEqual(result['selector'],selector);self.assertEqual(result['maximumAllowance'],1200 if gate=='reviewed-plan' else (840 if gate in ('local-agent','completion') else 600))
            for destination in ['platform=iOS Simulator,name=iPhone','platform=iOS Simulator,id=booted']:
                with self.assertRaises(ValueError):simulator_gate.prepare(scheme,root,destination)
            with self.assertRaises(ValueError):simulator_gate.prepare(scheme,root,'platform=iOS Simulator,id=12345678-1234-1234-1234-123456789abc','unknown')
            (root/download.MODELS[download.DEFAULT_MODEL_ID]['fileName']).write_bytes(b'wrong')
            with self.assertRaises(ValueError):simulator_gate.prepare(scheme,root,'platform=iOS Simulator,id=12345678-1234-1234-1234-123456789abc')
    def test_xctest_pin_and_assertion_contract(self):
        helper=(ROOT/'Tests/ProductionModelFixture.swift').read_text()
        for key,pin in download.MODELS.items():
            self.assertIn(key,helper);self.assertIn(pin['fileName'],helper);self.assertIn(pin['sha256'],helper)
            self.assertIn(f"{pin['byteCount']:,}".replace(',','_'),helper)
        agent=(ROOT/'Tests/ProductionLocalAgentSessionTests.swift').read_text()
        for required in ['ProductionModelFixture.descriptor','snapshot.answer?.contains(marker)','XCTAssertLessThan(searchIndex, readIndex)','original.write(to: manifest','XCTAssertTrue(cleanupFinished']:
            self.assertIn(required,agent)

class PipelineTests(unittest.TestCase):
    def run_pipeline(self, statuses):
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp);bin=root/'bin';bin.mkdir();(root/'scripts').mkdir()
            def put(name,text,executable=False):
                p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
                if executable:p.chmod(0o755)
            put('scripts/ci_native_inference.sh',(ROOT/'scripts/ci_native_inference.sh').read_text())
            for name in ['materialize_guest.py','download_test_model.py','boot_ci_simulator.py']:put('scripts/'+name,'pass\n')
            put('scripts/bootstrap_llama.sh','exit 0\n')
            for name in ['xcodegen','git','xcodebuild']:put('bin/'+name,'#!/bin/sh\necho mock\n',True)
            put('bin/xcrun','#!/bin/sh\necho \'{"devices":{"iOS-26":[{"name":"iPhone 16 Plus","udid":"12345678-1234-1234-1234-123456789abc","isAvailable":true}]}}\'\n',True)
            put('Diagnostics/VisionProof/prepare_production_pair.py','pass\n')
            put('Diagnostics/NativeTools/download.py','pass\n')
            put('Diagnostics/VisionProof/run_production_simulator.sh','echo vision >> "$TRACE"\nexit "$VISION_EXIT"\n')
            put('Diagnostics/NativeTools/run_production_simulator.sh','echo "$ORIVYN_PRODUCTION_MODEL_ID $NATIVE_TOOLS_GATE_KIND $ORIVYN_NATIVE_TOOLS_MODEL_DIR" >> "$TRACE"\nif [[ "$NATIVE_TOOLS_GATE_KIND" == reviewed-plan ]]; then exit "$REVIEWED_EXIT"; elif [[ "$NATIVE_TOOLS_GATE_KIND" == local-agent ]]; then exit "$AGENT_EXIT"; elif [[ "$ORIVYN_PRODUCTION_MODEL_ID" == qwen3-1.7b-q8_0 ]]; then exit "$Q8_EXIT"; else exit "$Q4_EXIT"; fi\n')
            env=dict(os.environ,PATH=str(bin)+os.pathsep+os.environ['PATH'],RUNNER_TEMP=str(root/'temp'),ORIVYN_COMBINED_RUNTIME_ARCHIVE='fixture',ORIVYN_NATIVE_FEATURES='ORIVYN_NATIVE_TOOLS ORIVYN_NATIVE_VISION',TRACE=str(root/'trace'),**dict(zip(['VISION_EXIT','Q8_EXIT','Q4_EXIT','AGENT_EXIT','REVIEWED_EXIT'],map(str,statuses))))
            result=subprocess.run(['bash',str(root/'scripts/ci_native_inference.sh')],env=env,capture_output=True,text=True,timeout=15)
            self.assertEqual(result.returncode==0,not any(statuses),result.stderr)
            self.assertEqual((root/'artifacts/production-inference/outcomes.txt').read_text(),f'vision={statuses[0]}\nnative_tools_q8={statuses[1]}\nnative_tools_q4={statuses[2]}\nlocal_agent_q4={statuses[3]}\nreviewed_plan_q4={statuses[4]}\n')
            trace=(root/'trace').read_text().splitlines();self.assertEqual(len(trace),5)
            self.assertEqual(trace[0],'vision');self.assertIn('qwen3-1.7b-q8_0 native-tools',trace[1]);self.assertIn('qwen3-1.7b-q4_k_m native-tools',trace[2]);self.assertIn('qwen3-1.7b-q4_k_m local-agent',trace[3]);self.assertIn('qwen3-1.7b-q4_k_m reviewed-plan',trace[4]);self.assertEqual(trace[3].split()[-1],trace[4].split()[-1]);self.assertEqual(trace[2].split()[-1],trace[3].split()[-1]);self.assertNotEqual(trace[1].split()[-1],trace[2].split()[-1])
    def test_all_success(self):self.run_pipeline([0,0,0,0,0])
    def test_independent_failures_preserved(self):self.run_pipeline([7,8,0,9,10])

    def test_only_new_gate_failure_is_fatal(self):self.run_pipeline([0,0,0,0,11])
    def test_each_original_gate_remains_required(self):
        for index in range(4):
            statuses=[0]*5;statuses[index]=19;self.run_pipeline(statuses)

class SimulatorRunnerTests(unittest.TestCase):
    def run_gate(self, build_status, summary, gate='native-tools'):
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp);bin=root/'bin';bin.mkdir();d=root/'Diagnostics/NativeTools';d.mkdir(parents=True)
            for name in ['download.py','simulator_gate.py','verify_simulator_result.py','run_production_simulator.sh']:(d/name).write_bytes((ROOT/'Diagnostics/NativeTools'/name).read_bytes())
            if gate == 'vision':
                vision=root/'Diagnostics/VisionProof';vision.mkdir();(vision/'run_production_simulator.sh').write_bytes((ROOT/'Diagnostics/VisionProof/run_production_simulator.sh').read_bytes())
            scheme=root/'JarvisEVO.xcodeproj/xcshareddata/xcschemes/JarvisEVO.xcscheme';scheme.parent.mkdir(parents=True);original='<Scheme><TestAction/></Scheme>';scheme.write_text(original)
            fixtures=root/'models';fixtures.mkdir();pin=download.select('qwen3-1.7b-q4_k_m')
            with (fixtures/pin['fileName']).open('wb') as f:f.truncate(pin['byteCount'])
            def command(name,text):
                p=bin/name;p.write_text('#!/bin/bash\n'+text);p.chmod(0o755)
            command('uname','echo Darwin\n');command('sysctl','echo 123\n');command('vm_stat','echo mock\n')
            command('xcodebuild','echo ORIVYN_PRODUCTION_VISION_REQUIRED_GATE_COMPLETED\nprintf "%s\\n" "$@" > "$ARGS"\nexit "$BUILD_EXIT"\n')
            command('xcrun','echo "$*" >> "$EXPORTS"\nif [[ "$*" == *"get test-results summary"* ]]; then echo "$SUMMARY"; fi\n')
            evidence=root/'evidence';env=dict(os.environ,PATH=str(bin)+os.pathsep+os.environ['PATH'],ORIVYN_NATIVE_TOOLS_MODEL_DIR=str(fixtures),NATIVE_TOOLS_DESTINATION='platform=iOS Simulator,id=12345678-1234-1234-1234-123456789abc',NATIVE_TOOLS_DERIVED_DATA=str(root/'derived'),NATIVE_TOOLS_EVIDENCE_DIR=str(evidence),ORIVYN_NATIVE_FEATURES='ORIVYN_NATIVE_TOOLS',ORIVYN_PRODUCTION_MODEL_ID='qwen3-1.7b-q4_k_m',NATIVE_TOOLS_GATE_KIND=gate,BUILD_EXIT=str(build_status),SUMMARY=json.dumps(summary),EXPORTS=str(root/'exports'),ARGS=str(root/'args'))
            if gate == 'vision':
                env.update(ORIVYN_NATIVE_FEATURES='ORIVYN_NATIVE_TOOLS ORIVYN_NATIVE_VISION',ORIVYN_VISION_MODEL_DIR=str(fixtures),VISION_DESTINATION=env['NATIVE_TOOLS_DESTINATION'],VISION_DERIVED_DATA=env['NATIVE_TOOLS_DERIVED_DATA'],VISION_EVIDENCE_DIR=str(evidence))
            runner=(root/'Diagnostics/VisionProof' if gate == 'vision' else d)/'run_production_simulator.sh'
            result=subprocess.run(['bash',str(runner)],env=env,capture_output=True,text=True,timeout=15)
            self.assertEqual(scheme.read_text(),original,'Scheme must restore on success or failure')
            exports=(root/'exports').read_text();self.assertIn('export attachments',exports);self.assertIn('get test-results summary',exports)
            self.assertIn(f'xcodebuild={build_status}\n',(evidence/'outcomes.txt').read_text())
            args=(root/'args').read_text();self.assertIn('ProductionVisionRuntimeTests/testRequiredProductionPNGInferenceAndRelease' if gate == 'vision' else simulator_gate.GATES[gate][2],args);self.assertIn('300' if gate == 'vision' else str(simulator_gate.GATES[gate][3]),args)
            return result.returncode
    def test_build_failure_exports_evidence_and_cannot_be_hidden_by_green_summary(self):
        self.assertNotEqual(self.run_gate(33,dict(totalTestCount=1,passedTests=1,failedTests=0,skippedTests=0)),0)
    def test_core_success_and_skip_are_distinct(self):
        self.assertEqual(self.run_gate(0,dict(totalTestCount=1,passedTests=1,failedTests=0,skippedTests=0),'local-agent'),0)
        self.assertNotEqual(self.run_gate(0,dict(totalTestCount=1,passedTests=0,failedTests=0,skippedTests=1),'local-agent'),0)

    def test_vision_failure_exports_and_preserves_build_status(self):
        summary=dict(totalTestCount=1,passedTests=1,failedTests=0,skippedTests=0)
        self.assertNotEqual(self.run_gate(33,summary,'vision'),0)
        self.assertEqual(self.run_gate(0,summary,'vision'),0)

    def test_reviewed_plan_failure_and_skip_cannot_pass(self):
        passed=dict(totalTestCount=1,passedTests=1,failedTests=0,skippedTests=0)
        self.assertEqual(self.run_gate(0,passed,'reviewed-plan'),0)
        self.assertNotEqual(self.run_gate(33,passed,'reviewed-plan'),0)
        self.assertNotEqual(self.run_gate(0,dict(totalTestCount=1,passedTests=0,failedTests=0,skippedTests=1),'reviewed-plan'),0)

    def test_completion_success_failure_and_skip_remain_distinct(self):
        passed=dict(totalTestCount=1,passedTests=1,failedTests=0,skippedTests=0)
        self.assertEqual(self.run_gate(0,passed,'completion'),0)
        self.assertNotEqual(self.run_gate(33,passed,'completion'),0)
        self.assertNotEqual(self.run_gate(0,dict(totalTestCount=1,passedTests=0,failedTests=0,skippedTests=1),'completion'),0)
