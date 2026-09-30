/// The short, human-readable reference shown for an order: `#78523600` —
/// its last 8 characters, uppercased. App-placed order ids are
/// `order-<micros>`, so the first 8 would read `ORDER-17…` on every order.
String orderReference(String orderId) =>
    '#${orderId.substring((orderId.length - 8).clamp(0, orderId.length)).toUpperCase()}';
