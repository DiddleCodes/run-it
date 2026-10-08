import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/notifications/push_notifications.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/chat/application/chat_controllers.dart';
import 'package:run_it/features/chat/data/chat_realtime.dart';
import 'package:run_it/features/chat/data/chat_repository.dart';
import 'package:run_it/features/chat/domain/chat_models.dart';
import 'package:run_it/features/chat/presentation/order_chat_screen.dart';
import 'package:run_it/features/runner/presentation/runner_messages_screen.dart';

import 'support/fake_chat.dart';

const _orderId = '6826e80f-051e-4bcc-8cd0-669e3e2c037d';
const _runnerId = 'runner-1';
const _studentId = 'student-1';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  @override
  AuthSession? build() => _session;
}

AuthSession _session(String userId, AccountType type) => AuthSession(
  accessToken: 'a',
  refreshToken: 'r',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: UserProfile(id: userId, name: 'Amaka Nwosu', contact: '+2348000000000', accountType: type),
);

ChatMessage _message(String id, String from, String body, {DateTime? readAt}) =>
    ChatMessage(id: id, orderId: _orderId, senderUserId: from, body: body, createdAt: DateTime(2026, 9, 30, 19, 5), readAt: readAt);

OrderChat _chat({bool canSend = true, List<ChatMessage> messages = const []}) => OrderChat(
  orderId: _orderId,
  canSend: canSend,
  vendorName: 'Golden Crust Bakery',
  otherPartyName: 'Ayanfe O.',
  messages: messages,
);

Future<(FakeChatRepository, FakeChatRealtime, ProviderContainer)> _pumpChat(
  WidgetTester tester, {
  OrderChat? chat,
}) async {
  final repository = FakeChatRepository(myUserId: _runnerId, chat: chat ?? _chat());
  final realtime = FakeChatRealtime();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _FakeAuthController(_session(_runnerId, AccountType.runner))),
        chatRepositoryProvider.overrideWithValue(repository),
        chatRealtimeProvider.overrideWithValue(realtime),
      ],
      child: const MaterialApp(home: OrderChatScreen(orderId: _orderId)),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(OrderChatScreen)));
  return (repository, realtime, container);
}

void main() {
  group('Task 78: order chat screen', () {
    testWidgets('shows the real conversation with who it is and which order, and joins its live room', (tester) async {
      final (repository, realtime, _) = await _pumpChat(
        tester,
        chat: _chat(messages: [_message('m1', _studentId, 'Which gate?'), _message('m2', _runnerId, 'Main gate', readAt: DateTime.now())]),
      );

      expect(find.text('Ayanfe O.'), findsOneWidget);
      expect(find.text('Order #3E2C037D · Golden Crust Bakery'), findsOneWidget);
      expect(find.text('Which gate?'), findsOneWidget);
      expect(find.text('Main gate'), findsOneWidget);
      expect(find.text('7:05 PM · Seen'), findsOneWidget); // read receipt on my own message only
      expect(realtime.joined, {_orderId});
      expect(repository.markReadCalls, greaterThan(0));
    });

    testWidgets('sending posts the message and shows it once, even when the room echoes it back', (tester) async {
      final (repository, realtime, _) = await _pumpChat(tester);

      await tester.enterText(find.byType(TextField), 'On my way');
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pumpAndSettle();

      expect(repository.sent, ['On my way']);
      // The same message comes back through the order's room.
      realtime.messageEvents.add(
        ChatMessage(id: 'sent-1', orderId: _orderId, senderUserId: _runnerId, body: 'On my way', createdAt: DateTime.now()),
      );
      await tester.pumpAndSettle();
      expect(find.text('On my way'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });

    testWidgets("the other side's message appears live, and is marked read because the chat is open", (tester) async {
      final (repository, realtime, _) = await _pumpChat(tester);
      final readsBefore = repository.markReadCalls;

      realtime.messageEvents.add(_message('m9', _studentId, 'I’m in the lobby'));
      await tester.pumpAndSettle();

      expect(find.text('I’m in the lobby'), findsOneWidget);
      expect(repository.markReadCalls, readsBefore + 1);
    });

    testWidgets('a failed send keeps the typed text and says so', (tester) async {
      final (repository, _, container) = await _pumpChat(tester);
      repository.failSends = true;

      await tester.enterText(find.byType(TextField), 'Hello?');
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Hello?');
      expect(container.read(appNotificationProvider).single.message, contains('Message not sent'));
    });

    testWidgets('a finished order shows its history but no composer', (tester) async {
      await _pumpChat(tester, chat: _chat(canSend: false, messages: [_message('m1', _studentId, 'Thanks!')]));

      expect(find.text('Thanks!'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('This order is finished, so its chat is closed.'), findsOneWidget);
    });
  });

  group("Task 78: the runner's Messages tab is real data", () {
    Future<void> pumpMessages(WidgetTester tester, FakeChatRepository repository) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const RunnerMessagesScreen()),
          GoRoute(path: AppRoutes.orderChat, builder: (_, state) => Text('chat for ${state.extra}')),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_session(_runnerId, AccountType.runner))),
            chatRepositoryProvider.overrideWithValue(repository),
            chatRealtimeProvider.overrideWithValue(FakeChatRealtime()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    final threads = [
      ChatThread(
        orderId: _orderId,
        canSend: true,
        vendorName: 'Golden Crust Bakery',
        otherPartyName: 'Ayanfe O.',
        unreadCount: 2,
        lastActivityAt: DateTime.now(),
        lastMessage: _message('m1', _studentId, 'Which gate?'),
      ),
      ChatThread(
        orderId: 'aaaaaaaa-0000-4000-8000-000000000001',
        canSend: false,
        vendorName: 'Tantalizers',
        otherPartyName: 'Tolu B.',
        unreadCount: 0,
        lastActivityAt: DateTime.now().subtract(const Duration(days: 1)),
        lastMessage: ChatMessage(
          id: 'm2',
          orderId: 'aaaaaaaa-0000-4000-8000-000000000001',
          senderUserId: _runnerId,
          body: 'Left it at reception',
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ),
    ];

    testWidgets('one thread per assigned order — no demo threads — with unread counts', (tester) async {
      await pumpMessages(tester, FakeChatRepository(threads: threads));

      expect(find.text('Ayanfe O.'), findsOneWidget);
      expect(find.text('#3E2C037D'), findsOneWidget);
      expect(find.text('Which gate?'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('You: Left it at reception'), findsOneWidget);
      expect(find.text('Bridgit Support'), findsNothing); // the old fake pinned thread is gone
    });

    testWidgets('tapping a thread opens that order’s chat', (tester) async {
      await pumpMessages(tester, FakeChatRepository(threads: threads));

      await tester.tap(find.text('Ayanfe O.'));
      await tester.pumpAndSettle();

      expect(find.text('chat for $_orderId'), findsOneWidget);
    });

    testWidgets('Support points to email (no support chat exists); Updates shows real notifications', (tester) async {
      await pumpMessages(
        tester,
        FakeChatRepository(
          notices: [AccountNotice(title: 'Order delivered', body: 'Nice one.', createdAt: DateTime.now(), unread: true)],
        ),
      );

      await tester.tap(find.text('Support'));
      await tester.pumpAndSettle();
      expect(find.textContaining('support@bridgitcampus.com'), findsOneWidget);

      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();
      expect(find.text('Order delivered'), findsOneWidget);
      expect(find.text('Peak hours incentive'), findsNothing); // the old fake notice
    });

    testWidgets('no assigned orders yet shows the empty state', (tester) async {
      await pumpMessages(tester, FakeChatRepository());
      expect(find.text('No messages yet'), findsOneWidget);
    });
  });

  group('Task 78: new-message banner while the app is open', () {
    ProviderContainer container(FakeChatRealtime realtime) {
      final c = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(() => _FakeAuthController(_session(_studentId, AccountType.student))),
          chatRealtimeProvider.overrideWithValue(realtime),
        ],
      );
      addTearDown(c.dispose);
      c.read(chatNoticeBannerProvider);
      return c;
    }

    test("banners a message in a chat that isn't on screen", () async {
      final realtime = FakeChatRealtime();
      final c = container(realtime);

      realtime.noticeEvents.add(_message('m1', _runnerId, 'Outside now'));
      await Future<void>.delayed(Duration.zero);

      expect(c.read(appNotificationProvider).single.message, 'New message: Outside now');
    });

    test('stays quiet for the chat already on screen, and for my own messages', () async {
      final realtime = FakeChatRealtime();
      final c = container(realtime);
      c.read(openChatOrderIdProvider.notifier).state = _orderId;

      realtime.noticeEvents
        ..add(_message('m1', _runnerId, 'Outside now'))
        ..add(
          ChatMessage(id: 'm2', orderId: 'other', senderUserId: _studentId, body: 'mine', createdAt: DateTime.now()),
        );
      await Future<void>.delayed(Duration.zero);

      expect(c.read(appNotificationProvider), isEmpty);
    });
  });

  test('Task 78: tapping a new-message push opens that order’s chat', () {
    expect(
      pushDestination(const PushMessage(data: {'type': 'chat_message', 'orderId': _orderId}), trackedOrderId: _orderId),
      AppRoutes.orderChat,
    );
  });
}
