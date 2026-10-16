#!/usr/bin/env python3
"""Credential-free feedback contracts: form and sheet import, Jev allocation, writer, form link.

Every fixture is synthetic. Company forms, member sheets and frameworks are
imported at run time and never belong in this repository.
"""
import argparse
import base64
from copy import deepcopy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import parse_qsl, urlsplit

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import pomodoro_feedback as feedback
from pomodoro_feedback import FeedbackError


def form_html(level_type=1, levels=None, extra=None):
    """A saved Google Form page in the shape FB_PUBLIC_LOAD_DATA_ takes."""
    levels = levels if levels is not None else [name for _, name, _ in feedback.LEVELS]
    items = [
        [1, 'Who is this for?', None, 2, [[100, [['Ops', None, 10, None, 0], ['Engineers', None, 20, None, 0]], 1]]],
        [10, 'Ops feedback', None, 8, None],
        [11, 'Name:', None, 3, [[110, [['О.Сарантуяа'], ['Б.Тэмүүлэн ']], 1]]],
        [20, 'Engineer feedback', None, 8, None],
        [21, 'Name:', None, 3, [[210, [['Д.Ганбаатар'], ['Э.Номин'], ['Х.Бат'], ['Ж.Тэмүүлэн']], 1]]],
        [30, 'Feedback', None, 8, None],
        *[[40 + index, f'{name} - write items.\n(numbered, SBI)', None, level_type, [[400 + index, None, 0]]]
          for index, name in enumerate(levels)],
        *(extra or []),
    ]
    data = [None, [None, items, None, None, None, None, None, None, 'Synthetic feedback'], '/forms', 'Synthetic']
    return ('<html><body><form action="https://docs.google.com/forms/u/0/d/e/1FAIpQLSynthetic_Form-Id/formResponse">'
            f'<script>var FB_PUBLIC_LOAD_DATA_ = {json.dumps(data, ensure_ascii=False)};</script></form></body></html>')


SHEET_HTML = """<table><tr><th></th><th>A</th><th>B</th><th>C</th><th>D</th><th>E</th></tr>
<tr><th>1</th><td>Name</td><td>Full name</td><td>Title</td><td>Department</td><td>Phone</td></tr>
<tr><th>2</th><td>Saraa</td><td>О.Сарантуяа</td><td>Project manager</td><td>Ops</td><td>99001122</td></tr>
<tr><th>3</th><td>Temka</td><td>Б. Тэмүүлэн</td><td>Senior Project<br>manager</td><td>Ops</td><td>99001133</td></tr>
<tr><th>4</th><td>Ganaa</td><td>Д.Ганбаатар</td><td>Intermediate Engineer</td><td>Team 1</td><td>99001144</td></tr>
<tr><th>5</th><td>Nomin</td><td>Э.Номин</td><td>Junior Engineer /PT/</td><td>Team 2</td><td>99001155</td></tr>
<tr><th>6</th><td>Bat</td><td>Х.Бат</td><td>Staff Engineer</td><td>Team 2</td><td>99001166</td></tr>
<tr><th>7</th><td>Other</td><td>Ч.Хэн</td><td>CEO</td><td>Board</td><td>99001177</td></tr></table>"""
SHEET_CSV = ('Last name,First name,Full name,Title,Department,Birthday\n'
             'Oyun,Sarantuya,О.Сарантуяа,Project manager,Ops,1.1\n'
             'Bold,Temuulen,Б.Тэмүүлэн,Senior Project manager,Ops,2.2\n'
             'Dorj,Ganbaatar,Д.Ганбаатар,Intermediate Engineer,Team 1,3.3\n')

FRAMEWORK = {
    'version': 'Synthetic 1.0',
    'ladders': {
        'eng': {'name': 'Engineering', 'grades': [
            {'id': 'G1', 'name': 'Junior', 'summary': 'Learns.'}, {'id': 'G2', 'name': 'Intermediate', 'summary': 'Independent.'},
            {'id': 'G3', 'name': 'Senior', 'summary': 'Leads.'}],
            'titleRules': [{'contains': 'senior', 'grade': 'G3'}, {'contains': 'intermediate', 'grade': 'G2'},
                           {'contains': 'junior', 'grade': 'G1'}]},
        'ops': {'name': 'Ops', 'grades': [{'id': 'owner', 'name': 'Owner'}, {'id': 'system', 'name': 'System owner'}],
                'titleRules': [{'contains': 'senior', 'grade': 'system'}, {'contains': '', 'grade': 'owner'}]},
    },
    'groups': {
        'Engineers': {'ladder': 'eng', 'competencies': ['team', 'craft', 'lead']},
        'Ops': {'ladder': 'ops', 'competencies': ['ops-team'],
                'roleRules': [{'contains': 'project manager', 'competency': 'delivery'}]},
    },
    'competencies': {
        'team': {'label': 'A-Team', 'name': 'Teamwork', 'description': '#Collaboration',
                 'cells': {'G1': 'Communicates clearly.', 'G2': 'Collaborates across teams.', 'G3': 'Leads team initiatives.'}},
        'craft': {'label': 'Craft', 'cells': {'G1': 'Simple code.', 'G2': 'Clean code.', 'G3': 'Scalable code.'}},
        'lead': {'label': 'Lead', 'cells': {'G1': 'N/A', 'G2': 'Mentors one person.', 'G3': 'Mentors a team.'}},
        'ops-team': {'label': 'A-Team', 'cells': {'owner': 'Aligns scope.', 'system': 'Builds rhythm.'}},
        'delivery': {'label': 'PM/AM ops', 'cells': {'owner': 'No-surprises delivery.', 'system': 'Sets PM standards.'}},
    },
}


def setup():
    form = feedback.parse_form(form_html())
    members = {'people': feedback.parse_members(SHEET_HTML, form), 'overrides': {}}
    resolved = {member['key']: member for member in feedback.resolve_members(form, FRAMEWORK, members)}
    return form, members, resolved


SIGNED_IN = {'WHISTLER_EMAIL': 'me@example.mn', 'WHISTLER_SESSION_TOKEN': 'synthetic-session'}


def note(identity, text, **extra):
    return {'id': identity, 'member': 'Engineers:Д.Ганбаатар', 'date': '2026-10-03', 'text': text, 'createdAt': 1, **extra}


NOTES = [
    note('a', 'Ганбаатараас асуухад outage-ийн үед 2 цагт зассан, Номин бас тусалсан'),
    note('b', 'mentored Э.Номин on debugging', competency='lead'),
    note('c', 'PR reviews late', level='minimum', additions={'impact': 'release slipped a day'}, omit=['situation']),
]
JEV_ANSWERS = {'answers': {'competency_n1': {'choice': 'c2'}, 'level_n1': {'choice': 'l2'},
                           'level_n2': {'choice': 'unclear'}, 'competency_n3': {'choice': 'unclear'}}}
WRITER_CONTENT = ('```json\n{"items":[{"key":"n2","sentence":"PERSON_8-д debugging заасан.","missing":[]},'
                  '{"key":"n1","sentence":"Outage-ийн үед 30 минутад\\nзасаж, үргэлж тусалсан.","missing":["impact"]},'
                  '{"key":"n3","sentence":"PR review хоцорсон нь release-ийг саатуулсан.","missing":["situation","behavior"]}]}\n```')


class FeedbackTests(unittest.TestCase):
    def test_form_import(self):
        form = feedback.parse_form(form_html())
        self.assertEqual(form['url'], 'https://docs.google.com/forms/d/e/1FAIpQLSynthetic_Form-Id/viewform')
        self.assertEqual(form['groupEntry'], '100')
        self.assertEqual([(g['label'], g['nameEntry'], g['names']) for g in form['groups']],
                         [('Ops', '110', ['О.Сарантуяа', 'Б.Тэмүүлэн']),
                          ('Engineers', '210', ['Д.Ганбаатар', 'Э.Номин', 'Х.Бат', 'Ж.Тэмүүлэн'])])
        self.assertEqual([(level['id'], level['entry']) for level in form['levels']],
                         [('exceptional', '400'), ('exceeds', '401'), ('meets', '402'), ('minimum', '403'), ('needs', '404')])

    def test_form_import_fails_closed(self):
        for html, message in [
            ('<html>no form</html>', 'not a saved Google Form'),
            (form_html(level_type=0), 'not a paragraph field'),
            (form_html(levels=[name for _, name, _ in feedback.LEVELS][:4]), 'Needs significant improvement'),
            (form_html(extra=[[50, 'Exceeds expectation again', None, 1, [[500, None, 0]]]]), 'Exceeds expectation'),
        ]:
            with self.assertRaisesRegex(FeedbackError, message):
                feedback.parse_form(html)

    def test_member_import_keeps_only_listed_people_and_three_columns(self):
        form = feedback.parse_form(form_html())
        people = feedback.parse_members(SHEET_HTML, form)
        self.assertEqual(people[1], {'name': 'Б. Тэмүүлэн', 'latin': '', 'title': 'Senior Project manager', 'department': 'Ops'})
        self.assertEqual([person['name'] for person in people], ['О.Сарантуяа', 'Б. Тэмүүлэн', 'Д.Ганбаатар', 'Э.Номин', 'Х.Бат'])
        self.assertNotIn('99001122', json.dumps(people))
        self.assertEqual(feedback.parse_members(SHEET_CSV, form)[2],
                         {'name': 'Д.Ганбаатар', 'latin': 'Ganbaatar Dorj', 'title': 'Intermediate Engineer', 'department': 'Team 1'})
        self.assertNotIn('3.3', json.dumps(feedback.parse_members(SHEET_CSV, form)))
        with self.assertRaisesRegex(FeedbackError, 'more than once'):
            feedback.parse_members(SHEET_CSV + 'D,G,Д.Ганбаатар,Senior Engineer,Team 1,4.4\n', form)
        with self.assertRaisesRegex(FeedbackError, 'Title'):
            feedback.parse_members('Name\nД.Ганбаатар\n', form)
        with self.assertRaisesRegex(FeedbackError, 'No column'):
            feedback.parse_members('Name,Title\nNobody,CEO\n', form)

    def test_members_resolve_from_titles_rules_and_overrides(self):
        form, members, resolved = setup()
        self.assertEqual({key: (m['grade'], m['role'], m['competencies'], m['issues']) for key, m in resolved.items()}, {
            'Ops:О.Сарантуяа': ('owner', 'delivery', ['ops-team', 'delivery'], []),
            'Ops:Б.Тэмүүлэн': ('system', 'delivery', ['ops-team', 'delivery'], []),
            'Engineers:Д.Ганбаатар': ('G2', None, ['team', 'craft', 'lead'], []),
            'Engineers:Э.Номин': ('G1', None, ['team', 'craft'], []),
            'Engineers:Х.Бат': (None, None, [], ['noGrade']),
            'Engineers:Ж.Тэмүүлэн': (None, None, [], ['notInSheet', 'noGrade']),
        })
        members['overrides'] = {'Engineers:Х.Бат': {'grade': 'G3'}, 'Engineers:Ж.Тэмүүлэн': {'grade': 'missing'}}
        again = {m['key']: m for m in feedback.resolve_members(form, FRAMEWORK, members)}
        self.assertEqual((again['Engineers:Х.Бат']['grade'], again['Engineers:Х.Бат']['gradeName']), ('G3', 'Senior'))
        self.assertIn('noGrade', again['Engineers:Ж.Тэмүүлэн']['issues'])
        unknown = deepcopy(FRAMEWORK)
        del unknown['groups']['Ops']
        self.assertEqual(feedback.resolve_members(form, unknown, members)[0]['issues'], ['unknownGroup'])
        broken = deepcopy(FRAMEWORK)
        broken['groups']['Ops']['competencies'].append('missing')
        with self.assertRaisesRegex(FeedbackError, 'malformed'):
            feedback.validate_framework(broken)

    def test_setup_bundle_fills_in_what_was_not_imported(self):
        form, members, _ = setup()
        bundle = feedback.setup_bundle(FRAMEWORK, form, {**members, 'overrides': {'Engineers:Х.Бат': {'grade': 'G3'}}})
        self.assertEqual(set(bundle), {'version', 'framework', 'form', 'members'})
        self.assertNotIn('overrides', bundle['members'])
        self.assertEqual(feedback.merge_setup(None, None, None, bundle), (FRAMEWORK, form, {'people': members['people'], 'overrides': {}}))
        own_form = {**form, 'title': 'Mine'}
        overrides = {'Engineers:Х.Бат': {'grade': 'G1'}}
        merged = feedback.merge_setup(None, own_form, {'overrides': overrides}, bundle)
        self.assertEqual((merged[1]['title'], merged[2]), ('Mine', {'people': members['people'], 'overrides': overrides}))
        imported = feedback.merge_setup(None, None, {'importedAt': 1, 'people': [], 'overrides': {}}, bundle)
        self.assertEqual(imported[2]['people'], [])
        for missing in [(None, form), (FRAMEWORK, None)]:
            with self.assertRaisesRegex(FeedbackError, 'Import the'):
                feedback.merge_setup(*missing, None, None)

    def test_member_keys_from_the_command_line_are_composed(self):
        import unicodedata
        with tempfile.TemporaryDirectory() as directory:
            form, members, _ = setup()
            form['groups'][0]['names'].append('Э. Байгаль')
            bundle = Path(directory) / 'feedback-setup.dat'
            bundle.write_bytes(feedback.seal_setup(feedback.setup_bundle(FRAMEWORK, form, members), ['example.mn']))
            with patch.object(feedback, 'BUNDLED_SETUP', bundle), \
                    patch.object(feedback, 'FRAMEWORK_FILE', Path(directory) / 'none'), \
                    patch.object(feedback, 'FORM_FILE', Path(directory) / 'none'), \
                    patch.object(feedback, 'MEMBERS_FILE', Path(directory) / 'none'):
                decomposed = unicodedata.normalize('NFD', 'Ops:Э. Байгаль')
                self.assertNotEqual(decomposed, 'Ops:Э. Байгаль')
                self.assertEqual(feedback.find_member(decomposed, SIGNED_IN)[2]['key'], 'Ops:Э. Байгаль')

    def test_sealed_setup_opens_only_for_signed_in_company_accounts(self):
        form, members, _ = setup()
        bundle = feedback.setup_bundle(FRAMEWORK, form, members)
        sealed = feedback.seal_setup(bundle, [' @Example.MN ', 'other.mn', ''])
        self.assertNotIn('Ганбаатар'.encode(), sealed)
        self.assertNotIn(b'Synthetic', sealed)
        opened = feedback.unseal_setup(sealed)
        self.assertEqual(opened, {**bundle, 'domains': ['example.mn', 'other.mn']})
        self.assertIsNone(feedback.unseal_setup(b'\x02' + sealed[1:]))
        self.assertIsNone(feedback.unseal_setup(sealed[:-3]))
        for config, expected in [(SIGNED_IN, True), ({**SIGNED_IN, 'WHISTLER_EMAIL': 'Me@OTHER.mn'}, True),
                                 ({**SIGNED_IN, 'WHISTLER_SESSION_TOKEN': ''}, False),
                                 ({**SIGNED_IN, 'WHISTLER_EMAIL': 'me@gmail.com'}, False),
                                 ({**SIGNED_IN, 'WHISTLER_EMAIL': 'me@sub.example.mn'}, False),
                                 ({**SIGNED_IN, 'WHISTLER_EMAIL': 'example.mn'}, False)]:
            self.assertEqual(feedback.opens_for(opened, config), expected, config)
        with self.assertRaises(FeedbackError):
            feedback.seal_setup(bundle, [' ', '@'])
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'feedback-setup.dat'
            path.write_bytes(sealed)
            none = Path(directory) / 'none'
            with patch.object(feedback, 'BUNDLED_SETUP', path), patch.object(feedback, 'FRAMEWORK_FILE', none), \
                    patch.object(feedback, 'FORM_FILE', none), patch.object(feedback, 'MEMBERS_FILE', none):
                self.assertEqual(feedback.load_setup(SIGNED_IN)[1]['title'], 'Synthetic feedback')
                with self.assertRaisesRegex(FeedbackError, 'Sign in to Whistler with your @example.mn account'):
                    feedback.load_setup({**SIGNED_IN, 'WHISTLER_EMAIL': 'me@gmail.com'})

    def test_names_are_hidden_with_suffixes_and_restored(self):
        form, _, _ = setup()
        names = feedback.Names(form)
        hidden = names.hide('Ганбаатараас асуухад, Э.Номин болон номин; Бат-Очир батлах Тэмүүлэн')
        self.assertNotRegex(hidden, 'Ганбаатар|Номин|Тэмүүлэн')
        self.assertIn(' номин; ', hidden)
        self.assertIn(' батлах ', hidden)
        self.assertRegex(hidden, r'^PERSON_\d+аас ')
        for text in ['Ганбаатараас', 'Бат-Очир', 'Э.Номинд', 'тэмүүлэн']:
            self.assertEqual(names.restore(names.hide(text)).casefold(), text.casefold())
        with self.assertRaisesRegex(FeedbackError, 'invented'):
            names.restore('PERSON_99')

    def test_allocation_payload_asks_only_open_decisions(self):
        form, _, resolved = setup()
        member = resolved['Engineers:Д.Ганбаатар']
        payload = feedback.allocation_payload(FRAMEWORK, member, NOTES, feedback.Names(form))
        self.assertEqual(payload['model'], 'typesafe/jev-1.13')
        self.assertEqual(sorted(payload['questions']), ['competency_n1', 'competency_n3', 'level_n1', 'level_n2'])
        self.assertEqual(payload['questions']['competency_n1']['criteria'],
                         {'c1': 'A-Team — Teamwork', 'c2': 'Craft', 'c3': 'Lead',
                          'unclear': 'The note does not say enough to tell which competency it shows.'})
        self.assertEqual(list(payload['questions']['level_n1']['criteria']), ['l1', 'l2', 'l3', 'l4', 'l5', 'unclear'])
        self.assertEqual(payload['state']['member'], {'group': 'Engineers', 'ladder': 'Engineering', 'grade': 'Intermediate',
                                                      'gradeSummary': 'Independent.', 'gradeBelow': 'Junior', 'gradeAbove': 'Senior'})
        self.assertEqual(payload['state']['competencies'][2],
                         {'key': 'c3', 'label': 'Lead', 'name': '', 'description': '', 'gradeBelow': 'N/A',
                          'ownGrade': 'Mentors one person.', 'gradeAbove': 'Mentors a team.'})
        self.assertEqual(payload['state']['notes'][2]['text'], 'PR reviews late\nImpact: release slipped a day')
        self.assertNotRegex(json.dumps(payload, ensure_ascii=False), 'Ганбаатар|Номин')
        top = feedback.allocation_payload(FRAMEWORK, {**member, 'grade': 'G3'}, NOTES[:1], feedback.Names(form))
        self.assertEqual((top['state']['member']['gradeBelow'], top['state']['member']['gradeAbove']), ('Intermediate', None))

    def test_allocation_reading_is_strict(self):
        form, _, resolved = setup()
        member = resolved['Engineers:Д.Ганбаатар']
        payload = feedback.allocation_payload(FRAMEWORK, member, NOTES, feedback.Names(form))
        self.assertEqual(feedback.read_allocation(JEV_ANSWERS, payload, member, NOTES),
                         [{'competency': 'craft', 'level': 'exceeds'}, {'competency': 'lead', 'level': None},
                          {'competency': None, 'level': 'minimum'}])
        for broken in [{'answers': {}}, None, {'answers': {**JEV_ANSWERS['answers'], 'extra': {'choice': 'c1'}}},
                       {'answers': {**JEV_ANSWERS['answers'], 'level_n1': {'choice': 'l9'}}},
                       {'answers': {**JEV_ANSWERS['answers'], 'level_n1': 'l1'}}]:
            with self.assertRaises(FeedbackError):
                feedback.read_allocation(broken, payload, member, NOTES)

    def test_writer_request_and_reading(self):
        form, _, resolved = setup()
        member, names = resolved['Engineers:Д.Ганбаатар'], feedback.Names(form)
        request = feedback.writer_request(member, NOTES, names)
        self.assertEqual(request['model'], feedback.WRITER_MODEL)
        user = json.loads(request['messages'][1]['content'])
        self.assertEqual(user['member'], {'group': 'Engineers', 'grade': 'Intermediate'})
        self.assertEqual(list(user['notes'][1]), ['key', 'date', 'note', 'omit'])
        self.assertEqual(user['notes'][2]['omit'], ['situation'])
        self.assertNotRegex(request['messages'][1]['content'], 'Ганбаатар|Номин')
        written = feedback.read_writer({'choices': [{'message': {'content': WRITER_CONTENT}}]}, NOTES, names)
        self.assertEqual(written, [
            {'sentence': 'Outage-ийн үед 30 минутад засаж, үргэлж тусалсан.', 'missing': ['impact']},
            {'sentence': 'Э.Номин-д debugging заасан.', 'missing': []},
            {'sentence': 'PR review хоцорсон нь release-ийг саатуулсан.', 'missing': ['behavior']}])
        for content in ['not json', '{"items":[]}', WRITER_CONTENT.replace('"n3"', '"n2"'),
                        WRITER_CONTENT.replace('"missing":[]', '"missing":["mood"]')]:
            with self.assertRaises(FeedbackError):
                feedback.read_writer({'choices': [{'message': {'content': content}}]}, NOTES, names)

    def test_checks_flag_unsupported_numbers_and_absolutes(self):
        self.assertEqual(feedback.checks('Outage-ийн үед 30 минутад, 2 цагт үргэлж тусалсан.', NOTES[0]),
                         ['number:30', 'word:үргэлж'])
        self.assertEqual(feedback.checks('10-р сарын 3-нд 2026 онд always', note('x', 'always helps')), [])
        self.assertEqual(feedback.checks('007 and 0', note('x', '7 or 00')), [])

    def test_improve_end_to_end_without_leaking_names(self):
        form, _, resolved = setup()
        member, calls = resolved['Engineers:Д.Ганбаатар'], []

        def request(url, **options):
            calls.append((url, options))
            self.assertEqual(options['headers']['Authorization'], 'Bearer synthetic-key')
            self.assertNotRegex(json.dumps(options['payload'], ensure_ascii=False), 'Ганбаатар|Номин')
            return JEV_ANSWERS if url == feedback.JEV_URL else {'choices': [{'message': {'content': WRITER_CONTENT}}]}

        drafts = feedback.improve(FRAMEWORK, member, NOTES, feedback.Names(form), 'synthetic-key', request)
        self.assertEqual(sorted(url for url, _ in calls), sorted([feedback.JEV_URL, feedback.WRITER_URL]))
        self.assertEqual([(d['noteId'], d['competency'], d['level'], d['questions']) for d in drafts], [
            ('a', 'craft', 'exceeds', ['impact', 'number:30', 'word:үргэлж']),
            ('b', 'lead', None, ['level']),
            ('c', None, 'minimum', ['competency', 'behavior'])])
        self.assertEqual(drafts[0]['basis'], feedback.basis(NOTES[0], member, FRAMEWORK))
        dismissed = [{**NOTES[0], 'dismissed': ['number:30', 'word:үргэлж']}]
        self.assertEqual(feedback.improve(FRAMEWORK, member, dismissed, feedback.Names(form), 'k', lambda url, **_:
                                          {'answers': {'competency_n1': {'choice': 'c1'}, 'level_n1': {'choice': 'l3'}}}
                                          if url == feedback.JEV_URL else {'choices': [{'message': {'content':
                                          '{"items":[{"key":"n1","sentence":"30 минут, үргэлж","missing":[]}]}'}}]})[0]['questions'], [])
        with self.assertRaisesRegex(FeedbackError, 'OpenRouter key'):
            feedback.improve(FRAMEWORK, member, NOTES, feedback.Names(form), '', request)
        with self.assertRaisesRegex(FeedbackError, 'no grade'):
            feedback.improve(FRAMEWORK, resolved['Engineers:Х.Бат'], NOTES, feedback.Names(form), 'k', request)
        self.assertEqual(feedback.improve(FRAMEWORK, member, [], feedback.Names(form), '', request), [])

    def test_basis_and_stale_notes(self):
        _, _, resolved = setup()
        member = resolved['Engineers:Д.Ганбаатар']
        current = {**NOTES[0], 'draft': {'basis': feedback.basis(NOTES[0], member, FRAMEWORK)}}
        edited = {**current, 'text': current['text'] + '!'}
        submitted = {**NOTES[1], 'submittedAt': 5}
        other = {**NOTES[2], 'member': 'Engineers:Э.Номин'}
        self.assertEqual([n['id'] for n in feedback.stale_notes([current, edited, submitted, other], member, FRAMEWORK)], ['a'])
        self.assertEqual(feedback.stale_notes([current], member, FRAMEWORK), [])
        self.assertEqual(feedback.stale_notes([{**edited, 'sentence': 'Written by hand.'}], member, FRAMEWORK), [])
        self.assertEqual(feedback.basis(NOTES[0], member, FRAMEWORK),
                         feedback.basis({**NOTES[0], 'level': 'needs', 'competency': 'team'}, member, FRAMEWORK))
        self.assertNotEqual(feedback.basis(NOTES[0], member, FRAMEWORK), feedback.basis(NOTES[0], {**member, 'grade': 'G3'}, FRAMEWORK))

    def test_form_answers_and_link(self):
        form, _, resolved = setup()
        member = resolved['Engineers:Д.Ганбаатар']
        drafted = feedback_notes(member)
        result = feedback.form_answers(form, FRAMEWORK, member, drafted)
        self.assertEqual(result['blockers'], [])
        self.assertEqual(result['fields'], {
            'exceeds': '1. [A-Team] Багийн sync-ийг удирдсан.\n2. [Craft] Refactor хийж, 40% хурдасгасан & цэвэрлэсэн.',
            'needs': '1. [Lead] Mentoring хийгээгүй.'})
        query = parse_qsl(urlsplit(result['url']).query)
        self.assertEqual(result['url'].split('?')[0], form['url'])
        self.assertEqual(query, [('usp', 'pp_url'), ('entry.100', 'Engineers'), ('entry.210', 'Д.Ганбаатар'),
                                 ('entry.401', result['fields']['exceeds']), ('entry.404', result['fields']['needs'])])
        self.assertIn('%0A2.%20%5BCraft%5D', result['url'])
        self.assertNotIn('+', result['url'])
        hinted = [*drafted, {**drafted[1], 'id': 'h', 'draft': {**drafted[1]['draft'], 'questions': ['impact', 'number:7']}}]
        self.assertEqual(feedback.form_answers(form, FRAMEWORK, member, hinted)['fields']['exceeds'].count('Багийн sync'), 2)
        chosen = {**drafted[2], 'id': 'u', 'text': 'changed', 'sentence': ' Гараар\nбичсэн. ', 'competency': 'team', 'level': 'meets'}
        self.assertEqual(feedback.form_answers(form, FRAMEWORK, member, [*drafted, chosen])['fields']['meets'],
                         '1. [A-Team] Гараар бичсэн.')
        blocked = [*drafted, {**drafted[0], 'id': 'q', 'draft': {**drafted[0]['draft'], 'level': None}},
                   {**drafted[0], 'id': 's', 'text': 'edited after drafting'},
                   {**drafted[0], 'id': 'c', 'text': 'edited after drafting', 'competency': 'team', 'level': 'meets'}]
        result = feedback.form_answers(form, FRAMEWORK, member, blocked)
        self.assertEqual((result['url'], result['blockers']),
                         (None, [{'noteId': 'q', 'reason': 'needsChoice'}, {'noteId': 's', 'reason': 'notConverted'},
                                 {'noteId': 'c', 'reason': 'notConverted'}]))
        self.assertIsNone(feedback.form_answers(form, FRAMEWORK, member, [])['url'])


def feedback_notes(member):
    rows = [('n3', '2026-10-05', 'craft', 'exceeds', 'Refactor хийж, 40% хурдасгасан & цэвэрлэсэн.'),
            ('n1', '2026-10-09', 'team', 'exceeds', 'Багийн sync-ийг удирдсан.'),
            ('n2', '2026-10-01', 'lead', 'needs', 'Mentoring хийгээгүй.')]
    notes = []
    for identity, day, competency, level, sentence in rows:
        item = note(identity, sentence, date=day)
        item['draft'] = {'basis': feedback.basis(item, member, FRAMEWORK), 'competency': competency, 'level': level,
                         'sentence': sentence, 'questions': []}
        notes.append(item)
    notes.append({**notes[0], 'id': 'old', 'submittedAt': 9})
    notes.append({**notes[0], 'id': 'elsewhere', 'member': 'Engineers:Э.Номин'})
    return notes


def native_fixture():
    """Inputs plus the Python results, so another implementation must reproduce them exactly."""
    form, members, resolved = setup()
    member = resolved['Engineers:Д.Ганбаатар']
    names = feedback.Names(form)
    payload = feedback.allocation_payload(FRAMEWORK, member, NOTES, names)
    allocations = feedback.read_allocation(JEV_ANSWERS, payload, member, NOTES)
    writer_response = {'choices': [{'message': {'content': WRITER_CONTENT}}]}
    drafted = feedback_notes(member)
    return {
        'formHtml': form_html(), 'sheetHtml': SHEET_HTML, 'sheetCsv': SHEET_CSV, 'framework': FRAMEWORK,
        'form': form, 'people': members['people'], 'peopleCsv': feedback.parse_members(SHEET_CSV, form),
        'members': feedback.resolve_members(form, FRAMEWORK, members),
        'overrides': {'Engineers:Х.Бат': {'grade': 'G3'}},
        'membersWithOverrides': feedback.resolve_members(form, FRAMEWORK, {**members, 'overrides': {'Engineers:Х.Бат': {'grade': 'G3'}}}),
        'memberKey': member['key'], 'notes': NOTES,
        'hidden': names.hide(NOTES[0]['text']), 'payload': payload, 'jevAnswers': JEV_ANSWERS, 'allocations': allocations,
        'writerRequest': feedback.writer_request(member, NOTES, names),
        'writerResponse': writer_response, 'written': feedback.read_writer(writer_response, NOTES, names),
        'checks': feedback.checks('Outage-ийн үед 30 минутад, 2 цагт үргэлж тусалсан.', NOTES[0]),
        'drafts': feedback.improve(FRAMEWORK, member, NOTES, names, 'k',
                                   lambda url, **_: JEV_ANSWERS if url == feedback.JEV_URL else writer_response),
        'bases': [feedback.basis(item, member, FRAMEWORK) for item in NOTES],
        'drafted': [*drafted, {**drafted[2], 'id': 'u', 'text': 'changed', 'sentence': 'Гараар бичсэн.', 'competency': 'team',
                                'level': 'meets'}, {**drafted[0], 'id': 'q', 'draft': {**drafted[0]['draft'], 'questions': ['impact']}}],
        'answers': feedback.form_answers(form, FRAMEWORK, member, [*drafted, {**drafted[2], 'id': 'u', 'text': 'changed',
                                         'sentence': 'Гараар бичсэн.', 'competency': 'team', 'level': 'meets'},
                                         {**drafted[0], 'id': 'q', 'draft': {**drafted[0]['draft'], 'questions': ['impact']}}]),
        'blockedNotes': [*drafted, {**drafted[0], 'id': 's', 'text': 'edited after drafting'}],
        'blockedAnswers': feedback.form_answers(form, FRAMEWORK, member, [*drafted, {**drafted[0], 'id': 's', 'text': 'edited after drafting'}]),
        'stale': [n['id'] for n in feedback.stale_notes([*drafted, {**drafted[0], 'id': 's', 'text': 'edited'},
                                                          {**drafted[0], 'id': 'm', 'text': 'edited', 'sentence': 'Mine.'}], member, FRAMEWORK)],
        'staleInput': [*drafted, {**drafted[0], 'id': 's', 'text': 'edited'}, {**drafted[0], 'id': 'm', 'text': 'edited', 'sentence': 'Mine.'}],
        'brokenForms': [form_html(level_type=0), '<html>no form</html>'],
        'bundle': feedback.setup_bundle(FRAMEWORK, form, members),
        'sealed': base64.b64encode(feedback.seal_setup(feedback.setup_bundle(FRAMEWORK, form, members), ['example.mn'], b'0123456789abcdef')).decode(),
        'sealedOpened': {**feedback.setup_bundle(FRAMEWORK, form, members), 'domains': ['example.mn']},
        'mergedFromBundle': list(feedback.merge_setup(None, None, {'overrides': {'Engineers:Х.Бат': {'grade': 'G3'}}},
                                                      feedback.setup_bundle(FRAMEWORK, form, members))),
    }


CS = r'''
using System.Text.Json;
using System.Text.Json.Nodes;
using Pomodoro.Core;
using Pomodoro.Integrations;

var fixture = JsonNode.Parse(File.ReadAllText(args[0]))!;
var options = new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
void Same(object? actual, string key, string what) {
    var node = actual as JsonNode ?? JsonSerializer.SerializeToNode(actual, options);
    if (!JsonNode.DeepEquals(node, fixture[key])) throw new Exception(what + " differs:\n" + node?.ToJsonString(options) + "\nexpected\n" + fixture[key]!.ToJsonString(options));
}
var form = Feedback.ParseForm(fixture["formHtml"]!.GetValue<string>());
Same(form, "form", "Form import");
foreach (var broken in fixture["brokenForms"]!.AsArray()) {
    try { Feedback.ParseForm(broken!.GetValue<string>()); throw new Exception("Broken form accepted"); } catch (FeedbackException) { }
}
var framework = Feedback.ValidateFramework(fixture["framework"]!.DeepClone().AsObject());
var people = Feedback.ParseMembers(fixture["sheetHtml"]!.GetValue<string>(), form);
Same(people, "people", "HTML member import");
Same(Feedback.ParseMembers(fixture["sheetCsv"]!.GetValue<string>(), form), "peopleCsv", "CSV member import");
var members = new JsonObject { ["people"] = people.DeepClone(), ["overrides"] = new JsonObject() };
var resolved = Feedback.ResolveMembers(form, framework, members);
Same(resolved, "members", "Member resolution");
members["overrides"] = fixture["overrides"]!.DeepClone();
Same(Feedback.ResolveMembers(form, framework, members), "membersWithOverrides", "Member overrides");
var member = resolved.AsArray().First(m => m!["key"]!.GetValue<string>() == fixture["memberKey"]!.GetValue<string>())!.AsObject();
var notes = fixture["notes"]!.AsArray().Select(n => n!.AsObject()).ToList();
var names = new FeedbackNames(form);
if (names.Hide(notes[0]["text"]!.GetValue<string>()) != fixture["hidden"]!.GetValue<string>()) throw new Exception("Name hiding differs");
var payload = Feedback.AllocationPayload(framework, member, notes, names);
Same(payload, "payload", "Jev payload");
var allocations = Feedback.ReadAllocation(fixture["jevAnswers"], payload, member, notes);
Same(allocations, "allocations", "Jev allocation");
Same(Feedback.WriterRequest(member, notes, names), "writerRequest", "Writer request");
Same(Feedback.ReadWriter(fixture["writerResponse"], notes, names), "written", "Writer reading");
Same(Feedback.Checks("Outage-ийн үед 30 минутад, 2 цагт үргэлж тусалсан.", notes[0]), "checks", "Checks");
Same(notes.Select(n => Feedback.Basis(n, member, framework)).ToList(), "bases", "Draft basis");
var drafts = await Feedback.ImproveAsync(framework, member, notes, names, "k", (url, body, ct) =>
    Task.FromResult<JsonNode?>(url == Feedback.JevUrl ? fixture["jevAnswers"]!.DeepClone() : fixture["writerResponse"]!.DeepClone()));
Same(drafts, "drafts", "Improve");
var drafted = fixture["drafted"]!.AsArray().Select(n => n!.AsObject()).ToList();
Same(Feedback.FormAnswers(form, framework, member, drafted), "answers", "Form answers and link");
Same(Feedback.FormAnswers(form, framework, member, fixture["blockedNotes"]!.AsArray().Select(n => n!.AsObject()).ToList()), "blockedAnswers", "Blocked form answers");
Same(Feedback.StaleNotes(fixture["staleInput"]!.AsArray().Select(n => n!.AsObject()), member, framework).Select(n => n["id"]!.GetValue<string>()).ToList(), "stale", "Notes to convert");
try { await Feedback.ImproveAsync(framework, member, notes, names, "", (u, b, c) => Task.FromResult<JsonNode?>(null)); throw new Exception("Missing key accepted"); }
catch (FeedbackException) { }
var merged = Feedback.MergeSetup(null, null, new JsonObject { ["overrides"] = new JsonObject { ["Engineers:Х.Бат"] = new JsonObject { ["grade"] = "G3" } } },
    fixture["bundle"]!.DeepClone().AsObject());
Same(new JsonArray(merged.Framework.DeepClone(), merged.Form.DeepClone(), merged.Members.DeepClone()), "mergedFromBundle", "Bundled setup");
Same(Feedback.SetupBundle(framework, form, members), "bundle", "Setup bundle");
var opened = Feedback.UnsealSetup(Convert.FromBase64String(fixture["sealed"]!.GetValue<string>()));
Same(opened, "sealedOpened", "Unsealed setup");
if (!Feedback.OpensFor(opened!, " Me@Example.MN ", true) || Feedback.OpensFor(opened!, "me@example.mn", false)
    || Feedback.OpensFor(opened!, "me@gmail.com", true) || Feedback.OpensFor(opened!, "me@sub.example.mn", true) || Feedback.OpensFor(opened!, "example.mn", true))
    throw new Exception("The email-domain gate differs");
if (Feedback.UnsealSetup([2, 1, 2]) is not null) throw new Exception("A broken seal opened");
// Windows-only pieces the Mac does in Swift or through the Python bridge.
var work = Environment.GetEnvironmentVariable("POMODORO_DATA_DIR")!;
File.WriteAllText(Path.Combine(work, "form.html"), fixture["formHtml"]!.GetValue<string>());
File.WriteAllText(Path.Combine(work, "sheet.csv"), fixture["sheetCsv"]!.GetValue<string>());
try { Feedback.ImportMembers(Path.Combine(work, "sheet.csv")); throw new Exception("Members imported without a form"); } catch (FeedbackException) { }
Feedback.ImportForm(Path.Combine(work, "form.html"));
if (Feedback.ImportMembers(Path.Combine(work, "sheet.csv")) != 3) throw new Exception("Member import count differs");
File.WriteAllText(Path.Combine(work, "framework.json"), fixture["framework"]!.ToJsonString());
Feedback.ImportFramework(Path.Combine(work, "framework.json"));
Feedback.SetGrade("Engineers:Х.Бат", "G3");
Feedback.ImportMembers(Path.Combine(work, "sheet.csv"));
var loaded = Feedback.LoadSetup();
if (loaded.Members["overrides"]?["Engineers:Х.Бат"]?["grade"]?.GetValue<string>() != "G3") throw new Exception("Grade override lost on re-import");
if (loaded.Members["people"]!.AsArray()[2]!["latin"]!.GetValue<string>() != "Ganbaatar Dorj") throw new Exception("Latin name lost");
Feedback.ExportSetup(Path.Combine(work, "setup.json"));
var exported = JsonNode.Parse(File.ReadAllText(Path.Combine(work, "setup.json")))!;
if (exported["members"]?["overrides"] is not null || exported["form"]?["title"]?.GetValue<string>() != "Synthetic feedback") throw new Exception("Export differs");
if (!File.ReadAllText(Path.Combine(work, "setup.json")).Contains("Д.Ганбаатар")) throw new Exception("Export escaped Cyrillic");
File.Delete(Feedback.FormFile); File.Delete(Feedback.FrameworkFile);
if (Feedback.ImportSetup(Path.Combine(work, "setup.json")) != 3 || Feedback.LoadSetup().Members["overrides"]?["Engineers:Х.Бат"] is null)
    throw new Exception("Setup import lost people or overrides");

var legacy = notes[0].DeepClone().AsObject();
legacy["draft"] = new JsonObject { ["basis"] = "x", ["competency"] = "craft", ["level"] = null, ["sentence"] = "Drafted.", ["questions"] = new JsonArray("level", "impact", "number:30") };
legacy["level"] = "meets";
File.WriteAllText(Feedback.NotesFile, new JsonObject { ["version"] = 1, ["notes"] = new JsonArray(legacy) }.ToJsonString());
var stored = FeedbackNotes.Read();
var adopted = stored[0];
if (adopted["draft"] is not null || adopted["text"]!.GetValue<string>() != "" || adopted["sentence"]!.GetValue<string>() != "Drafted."
    || adopted["competency"]!.GetValue<string>() != "craft" || adopted["level"]!.GetValue<string>() != "meets"
    || adopted["hints"]!.ToJsonString() != "[\"impact\",\"number:30\"]") throw new Exception("Adopting a draft differs: " + adopted.ToJsonString());
if (File.ReadAllText(Feedback.NotesFile).Contains("outage")) throw new Exception("The typed note was kept after conversion");
var fresh = FeedbackNotes.New("Engineers:Д.Ганбаатар", "  new note  ", new DateTime(2026, 10, 16, 9, 0, 0));
if (fresh["text"]!.GetValue<string>() != "new note" || fresh["date"]!.GetValue<string>() != "2026-10-16" || !FeedbackNotes.Converting(fresh)) throw new Exception("New note differs");
var list = new List<JsonObject> { adopted, fresh };
if (FeedbackNotes.Ready(list, "Engineers:Д.Ганбаатар")) throw new Exception("A converting note counted as ready");
list.Remove(fresh);
if (!FeedbackNotes.Ready(list, "Engineers:Д.Ганбаатар") || FeedbackNotes.Submitted(list, "Engineers:Д.Ганбаатар")) throw new Exception("Ready/submitted differ");
var lines = FeedbackNotes.FormLines(list, member);
if (lines.Count != 5 || lines.Single(line => line.Level == "meets").Items.Count != 1) throw new Exception("Form lines differ");
adopted["submittedAt"] = 1.0;
if (!FeedbackNotes.Submitted(list, "Engineers:Д.Ганбаатар")) throw new Exception("Submitted differs");

var anchor = new DateTime(2026, 10, 1, 17, 30, 0);
var upcoming = FeedbackReminderSchedule.Occurrences(anchor, 3, 16 * 60, new DateTime(2026, 10, 5, 12, 0, 0), 3);
if (!upcoming.SequenceEqual(new[] { new DateTime(2026, 10, 7, 16, 0, 0), new DateTime(2026, 10, 10, 16, 0, 0), new DateTime(2026, 10, 13, 16, 0, 0) }))
    throw new Exception("Reminder occurrences differ");
if (FeedbackReminderSchedule.Due(anchor, 3, 16 * 60, anchor, new DateTime(2026, 10, 1, 18, 0, 0)) is not null) throw new Exception("Turning on fired a past reminder");
if (FeedbackReminderSchedule.Due(anchor, 3, 16 * 60, anchor, new DateTime(2026, 10, 4, 16, 0, 0)) != new DateTime(2026, 10, 4, 16, 0, 0)) throw new Exception("Due reminder missed");
if (FeedbackReminderSchedule.Due(anchor, 3, 16 * 60, new DateTime(2026, 10, 4, 16, 0, 0), new DateTime(2026, 10, 6, 9, 0, 0)) is not null) throw new Exception("Reminder repeated");
if (FeedbackReminderSchedule.Due(anchor, 3, 16 * 60, anchor, new DateTime(2026, 10, 12, 9, 0, 0)) != new DateTime(2026, 10, 10, 16, 0, 0)) throw new Exception("Missed reminders should show once, the latest");
Console.WriteLine("C# form/member import, Jev allocation, writer, checks and form link match Python; notes, setup files and reminders pass");
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dotnet')
    args = parser.parse_args()
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(FeedbackTests))
    if not result.wasSuccessful(): raise SystemExit(1)
    if not args.dotnet: return
    environment = {**os.environ, 'DOTNET_CLI_TELEMETRY_OPTOUT': '1', 'DOTNET_NOLOGO': '1'}
    with tempfile.TemporaryDirectory(prefix='pomodoro-feedback-') as tmp:
        directory = Path(tmp).resolve()
        (directory / 'fixture.json').write_text(json.dumps(native_fixture(), ensure_ascii=False), encoding='utf-8')
        (directory / 'Program.cs').write_text(CS, encoding='utf-8')
        (directory / 'FeedbackTest.csproj').write_text(f'''<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup>
<TargetFramework>net8.0</TargetFramework><OutputType>Exe</OutputType><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable><LangVersion>12</LangVersion>
</PropertyGroup><ItemGroup><ProjectReference Include="{ROOT / 'windows/src/Pomodoro.Integrations/Pomodoro.Integrations.csproj'}" /></ItemGroup></Project>''', encoding='utf-8')
        subprocess.run([args.dotnet, 'run', '--project', str(directory / 'FeedbackTest.csproj'), '-c', 'Release', '--',
                        str(directory / 'fixture.json')], check=True, env={**environment, 'POMODORO_DATA_DIR': str(directory)})


if __name__ == '__main__': main()
