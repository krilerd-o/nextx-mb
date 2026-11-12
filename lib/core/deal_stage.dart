/// Deal stages — mirrors the web's constants/dealStage.js (keep in sync).
const kDealDefaultStage = 'Qualification';
const kDealClosedWon = 'Closed Won';
const kDealClosedLost = 'Closed Lost';

const kDealStageProbability = <String, int>{
  'Qualification': 10,
  'Value Proposition': 30,
  'Proposal Sent': 60,
  'Negotiation': 80,
  kDealClosedWon: 100,
  kDealClosedLost: 0,
};

/// Forward pipeline (Closed Lost is a separate exit).
const kDealPipeline = ['Qualification', 'Value Proposition', 'Proposal Sent', 'Negotiation', kDealClosedWon];

int? dealProbabilityFor(Object? stage) => kDealStageProbability['${stage ?? ''}'];

bool isClosedDealStage(Object? stage) => '$stage' == kDealClosedWon || '$stage' == kDealClosedLost;

/// Next open stage, or null when closed / at the end.
String? nextDealStage(Object? stage) {
  final s = '${stage ?? ''}';
  if (isClosedDealStage(s)) return null;
  final i = kDealPipeline.indexOf(s);
  if (i < 0) return kDealPipeline.first;
  return i >= kDealPipeline.length - 1 ? null : kDealPipeline[i + 1];
}

/// Fields to save when moving a deal to [toStage] (like the web).
Map<String, dynamic> dealStagePayload(String toStage, {String? lostReason}) => {
  'deal_stage': toStage,
  if (dealProbabilityFor(toStage) != null) 'probability': dealProbabilityFor(toStage),
  if (toStage == kDealClosedLost && lostReason != null) 'closed_reason': lostReason,
};
