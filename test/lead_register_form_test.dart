import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/lead_register/lead_form.dart';

Map<String, dynamic> q(String id, String uitype, {bool required = false, Map<String, dynamic> extra = const {}}) =>
    {'id': id, 'uitype': uitype, 'label': id, 'required': required, ...extra};

void main() {
  final form = LeadFormDef({
    'id': 1,
    'name': 'Booth',
    'ui_type': 'card',
    'sections': [
      {
        'id': 's1',
        'questions': [
          q('name', 'Text', required: true, extra: {'map_to': 'lead_name'}),
          q('email', 'Email', required: true),
          q('solutions', 'MultiSelect', required: true, extra: {
            'allow_other': true,
            'options': [
              {'value': 'ISAAC AI', 'label': 'ISAAC AI'},
              {'value': 'ERP', 'label': 'ERP', 'go_to': 's3'},
            ],
          }),
        ],
      },
      {
        'id': 's2',
        'questions': [q('rep', 'PicklistUser')],
      },
      {
        'id': 's3',
        'questions': [
          q('has_crm', 'YesNo'),
          q('which', 'Text', required: true, extra: {
            'show_if': {'question_id': 'has_crm', 'op': 'eq', 'value': 'true'},
          }),
          q('pdpa', 'FormConsent', required: true),
          q('grid', 'FormChoiceGrid', required: true, extra: {'rows': ['A', 'B'], 'columns': ['1', '2']}),
        ],
      },
    ],
  });

  test('reads sections from a fill definition', () {
    expect(form.sections.length, 3);
    expect(form.sections.first.questions.length, 3);
  });

  test('required, email and Other validation', () {
    final s = form.sections.first;
    expect(leadValidateSection(s, {}).keys, containsAll(['name', 'email', 'solutions']));
    expect(leadValidateSection(s, {'name': 'A', 'email': 'bad', 'solutions': ['ISAAC AI']})['email'], isNotNull);
    expect(leadValidateSection(s, {'name': 'A', 'email': 'a@b.co', 'solutions': ['__other__']})['solutions'], isNotNull);
    expect(leadValidateSection(s, {'name': 'A', 'email': 'a@b.co', 'solutions': ['__other__'], 'solutions__other': 'POS'}), isEmpty);
  });

  test('conditional questions, consent and grids', () {
    final s = form.sections[2];
    var errs = leadValidateSection(s, {'has_crm': false, 'pdpa': true, 'grid': {'A': '1', 'B': '2'}});
    expect(errs, isEmpty);
    errs = leadValidateSection(s, {'has_crm': true, 'pdpa': false, 'grid': {'A': '1'}});
    expect(errs.keys, containsAll(['which', 'pdpa', 'grid']));
  });

  test('staff-only types hidden for the public, shown for staff', () {
    final rep = form.sections[1].questions.first;
    expect(rep.staffOnly, isTrue);
    expect(leadQuestionVisible(rep, {}, staff: false), isFalse);
    expect(leadQuestionVisible(rep, {}, staff: true), isTrue);
  });

  test('option go_to skips a section', () {
    expect(leadNextSection(form.sections, 0, {'solutions': ['ISAAC AI']}), 1);
    expect(leadNextSection(form.sections, 0, {'solutions': ['ERP']}), 2);
    expect(leadNextSection(form.sections, 2, {}), 3);
  });

  test('answer text and scan merge', () {
    final sol = form.sections.first.questions[2];
    expect(leadAnswerText(sol, {'solutions': ['ISAAC AI', '__other__'], 'solutions__other': 'POS'}), 'ISAAC AI, อื่นๆ: POS');
    final m = leadMergeScan({'name': 'Old'}, {'name': 'Wichai', 'email': 'w@d.co', 'line': ''});
    expect(m.answers['name'], 'Wichai');
    expect(m.filled, {'name', 'email'});
  });

  test('new question defaults cover form-only types', () {
    expect(leadNewQuestion('FormConsent')['required'], isTrue);
    expect((leadNewQuestion('RadioGroup')['options'] as List).length, 2);
    expect(leadNewQuestion('Email')['map_to'], 'email_1st');
    expect(leadNewQuestion('FormChoiceGrid')['rows'], isNotEmpty);
  });

  test('offline card text fills email, mobile, website and name by mapping', () {
    final f = LeadFormDef({
      'id': 2,
      'sections': [
        {
          'id': 's1',
          'questions': [
            q('fn', 'Text', extra: {'map_to': 'lead_firstname'}),
            q('ln', 'Text', extra: {'map_to': 'lead_lastname'}),
            q('mail', 'Email', extra: {'map_to': 'email_1st'}),
            q('mob', 'Phone', extra: {'map_to': 'mobile_1st'}),
            q('co', 'Text', extra: {'map_to': 'company_name'}),
            q('web', 'Link'),
          ],
        },
      ],
    });
    const text = 'DELTA LOGISTICS CO., LTD.\nWichai Thongdee\nSales Director\nT. 02-123-4567\nM. 081-234-5678\nwichai@delta.co.th\nwww.delta.co.th';
    final out = leadParseCardText(text, f);
    expect(out['mail'], 'wichai@delta.co.th');
    expect(out['mob'], '0812345678');
    expect(out['web'], 'www.delta.co.th');
    expect(out['co'], 'DELTA LOGISTICS CO., LTD.');
    expect(out['fn'], 'Wichai');
    expect(out['ln'], 'Thongdee');
    expect(leadParseCardText('', f), isEmpty);
  });
}
