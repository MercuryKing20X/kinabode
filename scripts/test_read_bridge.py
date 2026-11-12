#!/usr/bin/env python3
"""Integration tests use a real isolated Godot process and no model provider."""
from contextlib import contextmanager
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from habitat_godot import Reader, BridgeError

ROOT = Path(__file__).resolve().parents[1]
ENGINE = os.environ.get('HABITAT_GODOT', str(ROOT/'scripts/isolated_godot.py'))

class BridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='youqi-read-test-')
        cls.log = open(Path(cls.temp.name) / 'engine.log', 'w+')
        cls.process = subprocess.Popen([ENGINE, '--headless', '--path', str(ROOT / 'godot'), '--script', 'tests/read_bridge_host.gd', '--', '--readers=5'],
            env=dict(os.environ, HABITAT_DATA_DIR=cls.temp.name), stdout=cls.log, stderr=cls.log)
        cls.addClassCleanup(cls.cleanup)
        heartbeat = Path(cls.temp.name) / 'read-api/heartbeat.json'
        deadline = time.monotonic() + 15
        while not heartbeat.exists() and time.monotonic() < deadline:
            if cls.process.poll() is not None:
                cls.log.seek(0)
                raise RuntimeError(cls.log.read())
            time.sleep(0.05)
        if not heartbeat.exists():
            cls.log.seek(0)
            raise RuntimeError('Game did not start: ' + cls.log.read())

    @classmethod
    def cleanup(cls):
        cls.process.terminate()
        try:
            cls.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            cls.process.kill()
            cls.process.wait(timeout=5)
        cls.log.close()
        cls.temp.cleanup()

    @contextmanager
    def frozen_simulation(self):
        # A real ticking village changes snapshot_revision independently of reads.
        # Freeze only Main's simulation in this disposable host; the original
        # endpoint keeps servicing actual IPC, and action tests keep real ticks.
        def toggle(freeze):
            type(self)._freeze_serial = getattr(type(self), "_freeze_serial", 0) + 1
            serial = type(self)._freeze_serial
            folder = Path(self.temp.name)
            temporary = folder / 'fixture-simulation.json.tmp'
            temporary.write_text(json.dumps({'serial': serial, 'freeze': freeze}))
            temporary.replace(folder / 'fixture-simulation.json')
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                try:
                    reply = json.loads((folder / 'fixture-simulation-ack.json').read_text())
                    if reply['serial'] == serial and reply['freeze'] == freeze:
                        return
                except (OSError, ValueError, KeyError):
                    pass
                time.sleep(.01)
            raise RuntimeError('fixture simulation acknowledgement timed out')
        toggle(True)
        try:
            yield
        finally:
            toggle(False)

    def reader(self, resident='codex'):
        return Reader(self.temp.name, resident=resident)

    def test_fishing_mcp(self):
        reader=self.reader('companion-5')
        def call(action,args=None):
            response=reader.handle({'id':444,'method':'tools/call','params':{'name':'game_action','arguments':{'action':action,'arguments':args or {}}}})
            return json.loads(response['result']['content'][0]['text'])
        catalog=reader.handle({'id':443,'method':'tools/call','params':{'name':'game_actions','arguments':{}}})
        self.assertEqual(json.loads(catalog['result']['content'][0]['text'])['contract_version'],2)
        # Stop an authored idle route before asserting that a rejected action never moves.
        # The real world continues ticking between these independent MCP requests.
        self.assertTrue(call('stop')['ok'])
        snap=reader.observe();self.assertEqual(len(snap['fishing']['pens']),4)
        self.assertNotIn('spots',snap['fishing']['pens'][0])
        before=snap['self']['position']
        self.assertEqual(call('fish')['error'],'not_near_sea');self.assertEqual(reader.observe()['self']['position'],before)
        shore=snap['fishing']['coast_targets'][0]
        moved=call('move',{'x':shore['position'][0],'y':shore['position'][1]});self.assertTrue(moved['ok'],moved)
        deadline=time.monotonic()+25
        while time.monotonic()<deadline:
            snap=reader.observe()
            if not snap['self'].get('activity')=='walking':break
            time.sleep(.1)
        snap=reader.observe();self.assertTrue(snap['fishing']['nearby_shore'])
        accepted=call('fish');self.assertTrue(accepted['ok']);self.assertEqual(accepted['status'],'accepted')
        self.assertEqual(reader.observe()['fishing']['pending'],[])
        deadline=time.monotonic()+110;pending=[]
        while time.monotonic()<deadline:
            snap=reader.observe();pending=snap['fishing']['pending']
            if pending:break
            time.sleep(.1)
        self.assertEqual(len(pending),1);fish=pending[0];self.assertEqual(fish['owner_id'],'companion-5')
        self.assertTrue(fish['source_id'].startswith('home.sea.'))
        position=reader.observe()['self']['position'];target=snap['fishing']['pens'][-1]['id']
        placed=call('stock_fish',{'fish_id':fish['id'],'pen_id':target})
        self.assertTrue(placed['ok']);self.assertEqual(reader.observe()['self']['position'],position)
        self.assertFalse(call('stock_fish',{'fish_id':fish['id'],'pen_id':target})['ok'])
        self.assertEqual(self.reader('companion-4').request('act',{'intent':'release_fish','fish_id':fish['id']})['error'],'fish_not_owned')
        self.assertTrue(call('release_fish',{'fish_id':fish['id']})['ok'])
        for invalid in [{'action':'fish','arguments':{'actor_id':'human'}},{'action':'fish','arguments':{'target_id':target}},{'action':'move','arguments':{'x':True,'y':2}}]:
            response=reader.handle({'id':445,'method':'tools/call','params':{'name':'game_action','arguments':invalid}})
            self.assertTrue(response['result']['isError'])
        with self.assertRaises(BridgeError):Reader(self.temp.name,expected_world='wrong-world').request('read_actions')

    def test_map_catalog(self):
        reader=self.reader()
        page=reader.request('read_map',{'limit':1})
        self.assertTrue(page['ok']);self.assertEqual(page['total'],3)
        self.assertEqual(page['self_actor_id'],'codex')
        other=reader.request('read_map',{'limit':1,'offset':1,'revision':page['revision']})
        self.assertTrue(other['ok']);self.assertNotEqual(page['regions'][0]['id'],other['regions'][0]['id'])
        detail=reader.request('read_map',{'region_id':'pine'})
        self.assertEqual(detail['region']['availability'],'preview_only')
        self.assertFalse(detail['capabilities']['cross_island_travel'])
        self.assertIn('land',detail['region']);self.assertIn('version',detail['region']['pack'])
        self.assertEqual(reader.request('read_map',{'region_id':'missing'})['error'],'unknown_region')
        self.assertEqual(reader.request('read_map',{'offset':1})['error'],'stale_map')
        for invalid in [{'actor_id':'human'},{'limit':True},{'offset':-1},{'region_id':''},{'revision':2},{'limit':101}]:
            with self.assertRaises(BridgeError):reader.request('read_map',invalid)
        tool=reader.handle({'id':999,'method':'tools/call','params':{'name':'read_map','arguments':{'region_id':'moon'}}})
        self.assertFalse(tool['result']['isError'])
        tool=reader.handle({'id':999,'method':'tools/call','params':{'name':'read_map','arguments':[]}})
        self.assertTrue(tool['result']['isError'])

    def test_01_five_concurrent_clients(self):
        with self.frozen_simulation():
            identities = ['codex'] + ['companion-' + str(i) for i in range(2, 6)]
            with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
                snapshots = list(pool.map(lambda resident: self.reader(resident).observe(), identities))
            self.assertEqual([s['self_actor_id'] for s in snapshots], identities)
            self.assertEqual(len({s['snapshot_revision'] for s in snapshots}), 1)
            self.assertEqual(len({s['world_id'] for s in snapshots}), 1)
            for snapshot in snapshots:
                self.assertTrue(snapshot['ok'])
                self.assertEqual(snapshot['residents'], snapshots[0]['residents'])
                self.assertTrue(snapshot['capabilities']['model_chat'])

    def test_02_pagination_and_region_query(self):
        with self.frozen_simulation():
            first = self.reader().observe({'limit': 10})
            second = self.reader().observe({'limit': 100, 'offset': 10, 'revision': first['snapshot_revision']})
            third = self.reader().observe({'limit':100, 'offset':second['page']['next_offset'], 'revision':first['snapshot_revision']})
            ids = [o['id'] for o in first['objects'] + second['objects'] + third['objects']]
            self.assertEqual(len(ids), 126)  # Removed two world chests and eight farm containers.
            self.assertEqual(len(set(ids)), 126)
            self.assertTrue(all(o["kind"] != "chest" for o in first["objects"] + second["objects"] + third["objects"]))
            self.assertTrue(third['page']['complete'])
            island = self.reader().observe({'region_id': 'moon'})
            self.assertEqual(island['page']['total'], 0)
            self.assertEqual(island['region']['id'], 'moon')
            self.assertEqual(island['self']['region_id'], 'home')

    def test_03_cannot_impersonate_human(self):
        with self.assertRaises(BridgeError):
            self.reader('human').observe()
        with self.assertRaises(BridgeError):
            self.reader().observe({'actor_id': 'human'})
        with self.assertRaises(BridgeError):
            self.reader('not-provisioned').observe()

    def test_04_reads_do_not_mutate(self):
        with self.frozen_simulation():
            before = self.reader().observe()
            for _ in range(6):
                now = self.reader().observe()
                self.assertEqual(now['snapshot_revision'], before['snapshot_revision'])
                self.assertEqual(now['objects'], before['objects'])
                self.assertEqual(now['residents'], before['residents'])

    def test_05_mcp_only_advertises_real_capabilities(self):
        reader = self.reader()
        tools = reader.handle({'id': 1, 'method': 'tools/list'})['result']['tools']
        self.assertEqual([t['name'] for t in tools], ['observe_world', 'act', 'read_character', 'edit_character', 'read_work', 'edit_work','read_memories','read_map','fish_action','game_actions','game_action','dialogue_poll','dialogue_reply','habitat_persona'])
        result = reader.handle({'id': 2, 'method': 'tools/call', 'params': {'name': 'act', 'arguments': {'intent': 'chop'}}})
        self.assertTrue(result['result']['isError'])
        result = reader.handle({'id': 3, 'method': 'tools/call', 'params': {'name': 'observe_world', 'arguments': {'object_id': 'home.chest.01'}}})
        self.assertTrue(result['result']['isError'])  # A removed chest is no longer a readable world object.
        result = reader.handle({'id': 4, 'method': 'tools/call', 'params': {'name': 'observe_world', 'arguments': {}}})
        self.assertFalse(result['result']['isError'])
        snapshot = json.loads(result['result']['content'][0]['text'])
        self.assertIsInstance(snapshot['storage']['items'], dict)
        self.assertNotIn('home.chest.01', [obj['id'] for obj in snapshot['objects']])

    def test_06_offline_is_not_empty_world(self):
        with tempfile.TemporaryDirectory(prefix='youqi-offline-') as path:
            with self.assertRaisesRegex(BridgeError, 'game_unavailable'):
                Reader(path).observe()

    def test_07_cli_and_stdio(self):
        command = ['python3', str(ROOT / 'scripts/habitat_godot.py'), '--data-dir', self.temp.name]
        result = subprocess.run(command + ['observe', '--limit', '2'], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(json.loads(result.stdout)['objects']), 2)
        result = subprocess.run(command + ['mcp'], input='{"jsonrpc":"2.0","id":1,"method":"tools/list"}\n', capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['id'], 1)


    def test_08_real_action_is_bound_and_not_completion(self):
        reader=self.reader()
        before=reader.observe()
        result=reader.request('act',{'intent':'chop','target_id':'home.tree.01'})
        self.assertTrue(result['ok'],result)
        self.assertEqual(result['status'],'accepted')
        running=reader.observe()
        self.assertIn('codex',running['jobs'])
        self.assertEqual(next(a for a in before['residents'] if a['id']=='human'),next(a for a in running['residents'] if a['id']=='human'))
        self.assertFalse(reader.request('act',{'intent':'stop','actor_id':'human'})['ok'])
        self.assertTrue(reader.request('act',{'intent':'stop'})['ok'])
        self.assertNotIn('codex',reader.observe()['jobs'])

    def test_09_appearance_edit_keeps_residents_independent(self):
        reader=self.reader('companion-2')
        other=self.reader('companion-3')
        before=reader.request('read_character',{'frame':'down_0'})
        other_before=other.request('read_character',{'frame':'down_0'})
        self.assertNotEqual(before['artwork_id'],other_before['artwork_id'])
        patch={'base_revision':before['revision'],'frame':'down_0','layer':0,'pixels':[{'x':0,'y':0,'color':'#e81232ff'}]}
        self.assertTrue(reader.request('edit_character',patch)['ok'])
        self.assertEqual(other.request('read_character',{'frame':'down_0'}),other_before)
        self.assertEqual(reader.request('edit_character',patch)['error'],'stale_artwork')


    def test_10_shared_work_api(self):
        reader=self.reader()
        current=reader.request('read_work',{'artwork_id':'cottage','frame':'stage_4'})
        self.assertTrue(current['ok'])
        self.assertEqual(len(current['layers'][0]['pixels']),24*24)
        self.assertFalse(current['complete'])
        self.assertFalse(reader.request('read_work',{'artwork_id':'human-starter'})['ok'])
        changed=reader.request('edit_work',{'artwork_id':'cottage','base_revision':current['revision'],'structure':{'width':9,'depth':7,'floors':1,'porch':1}})
        self.assertTrue(changed['ok'],changed)
        selected=reader.request('act',{'intent':'select_blueprint','target_id':'home.house.01','blueprint_id':'cottage'})
        self.assertTrue(selected['ok'],selected)
        snapshot=reader.observe({'object_id':'home.house.01'})
        self.assertNotIn('artwork',snapshot['objects'][0]['blueprint'])
        self.assertEqual(snapshot['objects'][0]['blueprint']['structure']['width'],9)

if __name__ == '__main__':
    unittest.main(verbosity=2)
