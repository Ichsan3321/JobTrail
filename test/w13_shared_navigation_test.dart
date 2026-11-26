import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobtrail/app.dart';
import 'package:jobtrail/core/routes/app_navigation.dart';
import 'package:jobtrail/data/jobtrail_repository.dart';
import 'package:jobtrail/data/jobtrail_store.dart';
import 'package:jobtrail/screens/application_form/application_form_screen.dart';
import 'package:jobtrail/screens/detail/application_detail_screen.dart';
import 'package:jobtrail/widgets/app_shell.dart';

import 'jobtrail_persistence_test.dart'
    show TestSession, emptySnapshot, failsWith, mount, snapshot;
import 'jobtrail_repository_test.dart' show appId;
import 'jobtrail_store_test.dart' show draft;
import 'support/fake_jobtrail_repository.dart';

AppShell shell(WidgetTester tester) => tester.widget(find.byType(AppShell));

Future<AppNavigation> mountDemo(WidgetTester tester) async {
  await tester.pumpWidget(const JobTrailApp(showAuthentication: false));
  return shell(tester).navigation;
}

void main() {
  testWidgets('Add returns to Board with the exact saved ID', (tester) async {
    final navigation = await mountDemo(tester);
    final add = navigation.openAdd();
    await tester.pumpAndSettle();
    final savedId = navigation.store.addApplication(draft());

    navigation.finishForm(savedId);
    await add;
    await tester.pumpAndSettle();

    expect(navigation.selectedTab, AppTab.board);
    expect(navigation.savedBoardApplicationId, savedId);
    expect(find.byKey(ValueKey('application-$savedId')), findsOneWidget);
    expect(navigation.navigatorKey.currentState!.canPop(), isFalse);
  });

  testWidgets('Edit returns to the original Detail route and ID', (
    tester,
  ) async {
    final navigation = await mountDemo(tester);
    const id = 'app-nusa';
    unawaited(navigation.openDetail(id));
    await tester.pumpAndSettle();
    final detail = find.byType(ApplicationDetailScreen);
    final originalRoute = ModalRoute.of(tester.element(detail));

    final edit = navigation.openEdit(id);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ApplicationFormScreen>(find.byType(ApplicationFormScreen))
          .applicationId,
      id,
    );
    final original = navigation.store.applicationById(id)!;
    navigation.store.updateApplication(
      id,
      draft(company: 'Updated W13', appliedAt: original.appliedAt),
    );
    navigation.finishForm(id);
    await edit;
    await tester.pumpAndSettle();

    expect(ModalRoute.of(tester.element(detail)), same(originalRoute));
    expect(tester.widget<ApplicationDetailScreen>(detail).applicationId, id);
    expect(find.text('Updated W13'), findsOneWidget);
    expect(navigation.savedBoardApplicationId, isNull);
  });

  testWidgets('dirty Back allows continuing or discarding to the origin', (
    tester,
  ) async {
    final navigation = await mountDemo(tester);
    navigation.showTab(AppTab.documents);
    final before = navigation.store.applications
        .map((item) => item.id)
        .toList();
    final add = navigation.openAdd();
    await tester.pumpAndSettle();
    final company = find.byType(TextFormField).first;
    await tester.enterText(company, 'Unsaved change');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut mengisi'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved change'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buang perubahan'));
    await tester.pumpAndSettle();
    await add;

    expect(find.byType(ApplicationFormScreen), findsNothing);
    expect(navigation.selectedTab, AppTab.documents);
    expect(navigation.savedBoardApplicationId, isNull);
    expect(navigation.store.applications.map((item) => item.id), before);
  });

  testWidgets('abandoned Add completion leaves a newer Detail open', (
    tester,
  ) async {
    final navigation = await mountDemo(tester);
    final add = navigation.openAdd();
    await tester.pumpAndSettle();

    navigation.showTab(AppTab.documents);
    unawaited(navigation.openDetail('app-nusa'));
    await add;
    await tester.pumpAndSettle();

    expect(navigation.selectedTab, AppTab.documents);
    expect(navigation.savedBoardApplicationId, isNull);
    expect(
      tester
          .widget<ApplicationDetailScreen>(find.byType(ApplicationDetailScreen))
          .applicationId,
      'app-nusa',
    );
  });

  testWidgets('a saved Add result cannot replace a newer Detail route', (
    tester,
  ) async {
    final navigation = await mountDemo(tester);
    final add = navigation.openAdd();
    await tester.pumpAndSettle();
    final savedId = navigation.store.addApplication(draft());

    // Push a newer route before openAdd resumes from the popped result.
    navigation.finishForm(savedId);
    unawaited(navigation.openDetail('app-nusa'));
    await add;
    await tester.pumpAndSettle();

    expect(find.byType(ApplicationDetailScreen), findsOneWidget);
    expect(navigation.savedBoardApplicationId, isNull);
    expect(navigation.store.applicationById(savedId), isNotNull);
  });

  testWidgets('a saved Add result respects a newer tab selection', (
    tester,
  ) async {
    final navigation = await mountDemo(tester);
    final add = navigation.openAdd();
    await tester.pumpAndSettle();
    final savedId = navigation.store.addApplication(draft());

    navigation.finishForm(savedId);
    navigation.showTab(AppTab.documents);
    await add;
    await tester.pumpAndSettle();

    expect(navigation.selectedTab, AppTab.documents);
    expect(navigation.savedBoardApplicationId, isNull);
    expect(navigation.store.applicationById(savedId), isNotNull);
  });

  testWidgets('a saved Add result leaves a newer shell dialog open', (
    tester,
  ) async {
    final navigation = await mountDemo(tester);
    final shellContext = tester.element(find.byType(AppShell));
    final add = navigation.openAdd();
    await tester.pumpAndSettle();
    final savedId = navigation.store.addApplication(draft());

    navigation.finishForm(savedId);
    unawaited(
      showDialog<void>(
        context: shellContext,
        builder: (_) => const AlertDialog(title: Text('Newer dialog')),
      ),
    );
    await add;
    await tester.pumpAndSettle();

    expect(find.text('Newer dialog'), findsOneWidget);
    expect(navigation.selectedTab, AppTab.home);
    expect(navigation.savedBoardApplicationId, isNull);
  });

  testWidgets('a late receipt from the old account cannot route or refresh', (
    tester,
  ) async {
    final session = TestSession();
    final receipt = Completer<ApplicationCreateReceipt>();
    final old = FakeJobTrailRepository(() => snapshot('Previous account'));
    final replacement = FakeJobTrailRepository(() => snapshot('New account'));
    old.create = (_, _) => receipt.future;
    await mount(tester, session, (id) => id == 'owner-a' ? old : replacement);
    final from = shell(tester);
    final intent = ApplicationCreation(draft());
    final rejected = expectLater(
      from.store.createApplicationRemote(intent),
      failsWith(RepositoryIssue.authentication),
    );
    expect(from.store.isMutating, isTrue);
    final reads = old.reads;

    session.changes.add(session.signedIn('owner-b'));
    await tester.pumpAndSettle();
    final current = shell(tester);
    expect(old.disposed, isTrue);
    expect(current.navigation, isNot(same(from.navigation)));
    expect(current.store.applicationById(appId)?.company, 'New account');
    current.navigation.showTab(AppTab.documents);
    unawaited(current.navigation.openDetail(appId));
    await tester.pumpAndSettle();

    receipt.complete((id: intent.id, revision: 1, replayed: false));
    await rejected;
    await tester.pumpAndSettle();

    expect(old.reads, reads);
    expect(current.store.applicationById(intent.id), isNull);
    expect(current.navigation.selectedTab, AppTab.documents);
    expect(current.navigation.savedBoardApplicationId, isNull);
    expect(find.byType(ApplicationDetailScreen), findsOneWidget);
  });

  testWidgets('connected Add and Edit stay gated across snapshot phases', (
    tester,
  ) async {
    final session = TestSession();
    final initial = Completer<JobTrailSnapshot>();
    final repo = FakeJobTrailRepository(() => initial.future);
    var createCalls = 0;
    repo.create = (id, _) {
      createCalls++;
      return (id: id, revision: 1, replayed: false);
    };
    await mount(tester, session, (_) => repo);

    // The signed-in loading screen has no shell and no form entry.
    expect(find.byType(AppShell), findsNothing);
    expect(find.byType(ApplicationFormScreen), findsNothing);
    initial.complete(snapshot());
    await tester.pumpAndSettle();
    final account = shell(tester);
    final store = account.store;
    final navigation = account.navigation;

    Future<void> expectEntriesClosed() async {
      await navigation.openAdd();
      await navigation.openEdit(appId);
      await tester.pumpAndSettle();
      expect(find.byType(ApplicationFormScreen), findsNothing);
      expect(navigation.navigatorKey.currentState!.canPop(), isFalse);
    }

    expect(store.phase, StorePhase.ready);
    await expectEntriesClosed();

    repo.read = emptySnapshot;
    await store.refresh();
    expect(store.phase, StorePhase.empty);
    expect(store.hasSnapshot, isTrue);
    await expectEntriesClosed();

    repo.read = () => throw const RepositoryFailure(RepositoryIssue.network);
    await store.refresh();
    expect(store.phase, StorePhase.error);
    expect(store.hasSnapshot, isTrue, reason: 'Retained snapshot is stale.');
    await expectEntriesClosed();
    await expectLater(
      store.createApplicationRemote(ApplicationCreation(draft())),
      failsWith(RepositoryIssue.busy),
    );

    await session.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsNothing);
    expect(repo.disposed, isTrue);
    await navigation.openAdd();
    await navigation.openEdit(appId);
    await expectLater(
      store.createApplicationRemote(ApplicationCreation(draft())),
      failsWith(RepositoryIssue.authentication),
    );
    expect(find.byType(ApplicationFormScreen), findsNothing);
    expect(createCalls, 0);
  });
}
