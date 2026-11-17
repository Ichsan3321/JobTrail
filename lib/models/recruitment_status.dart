enum RecruitmentStatus {
  applied('Applied'),
  screening('Screening'),
  test('Test/Psikotes'),
  interview('Interview'),
  offering('Offering'),
  rejected('Rejected');

  const RecruitmentStatus(this.label);
  final String label;
}
