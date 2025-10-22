import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert'; // For json.decode
import 'package:intl/intl.dart'; // For date formatting
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// DATA_MODEL
class Vegetable {
  final int id;
  final String name;
  final double price;
  final String? imageUrl;

  Vegetable(this.id, this.imageUrl, {required this.name, required this.price});

  factory Vegetable.fromJson(Map<String, dynamic> json) {
    return Vegetable(
      json['id'] as int,
      json['imageUrl'] as String?,
      name: json['name'] ?? 'Unknown', // ถ้า name null ให้เป็น 'Unknown'
      price: (json['price'] as num?)?.toDouble() ?? 0.0, // ✅ ป้องกัน null
    );
  }
}

class CartItem {
  final Vegetable vegetable;
  int quantity;

  CartItem({required this.vegetable, this.quantity = 1});

  void incrementQuantity() {
    quantity++;
  }

  void decrementQuantity() {
    quantity--;
  }

  double get totalPrice => vegetable.price * quantity; // Changed to double
}

class OrderedVegetable {
  final Vegetable vegetable;
  final double quantity;
  final double itemTotalPrice; // Changed to double

  OrderedVegetable({required this.vegetable, required this.quantity})
    : itemTotalPrice =
          vegetable.price * quantity; // Now correctly assigns a double
}

class OrderSummary {
  final List<OrderedVegetable> items;
  final double originalTotalAmount;
  final double discountValue;
  final double finalTotalAmount;
  final DateTime orderDate;

  OrderSummary({
    required this.items,
    required this.originalTotalAmount,
    required this.discountValue,
    required this.finalTotalAmount,
    required this.orderDate,
  });

  /// จาก JSON
  factory OrderSummary.fromJson(Map<String, dynamic> json) {
    final List<OrderedVegetable> items = (json['items'] as List ?? []).map((
      item,
    ) {
      final veg = Vegetable(
        item['productId'] ?? 0,
        null,
        name: item['name'] ?? 'Unknown',
        price: (item['price'] ?? 0).toDouble(),
      );
      return OrderedVegetable(
        vegetable: veg,
        quantity: (item['quantity'] ?? 0.0),
      );
    }).toList();

    final double totalPrice = (json['totalPrice'] ?? 0).toDouble();
    final double discount = (json['discount'] ?? 0).toDouble();

    return OrderSummary(
      items: items,
      originalTotalAmount: (json['totalPrice'] as num).toDouble(),
      discountValue: (json['discount'] ?? 0).toDouble(),
      finalTotalAmount: (json['totalPrice'] as num).toDouble(),
      orderDate: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  /// จาก CartModel (สร้างใหม่)
  factory OrderSummary.fromCartModel(CartModel cartModel) {
    final List<OrderedVegetable> orderedItems = cartModel.items
        .map<OrderedVegetable>(
          (cartItem) => OrderedVegetable(
            vegetable: cartItem.vegetable,
            quantity: cartItem.quantity.toDouble(), // แปลงเป็น double
          ),
        )
        .toList();

    return OrderSummary(
      items: orderedItems,
      originalTotalAmount: cartModel.originalTotalAmount.toDouble(),
      discountValue: cartModel.discountValue.toDouble(),
      finalTotalAmount: cartModel.finalTotalAmount.toDouble(),
      orderDate: DateTime.now(),
    );
  }
}

class CartModel extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  List<CartItem> get items => _items.values.toList();

  double get originalTotalAmount {
    // Changed to double
    double total = 0.0; // Initialize as double
    _items.forEach((String key, CartItem cartItem) {
      total += cartItem.totalPrice;
    });
    return total;
  }

  bool get hasDiscountApplied => originalTotalAmount > 100;

  double get discountValue {
    if (hasDiscountApplied) {
      return originalTotalAmount * 0.10;
    }
    return 0.0;
  }

  double get finalTotalAmount {
    return originalTotalAmount - discountValue;
  }

  void addToCart(Vegetable veg) {
    if (_items.containsKey(veg.name)) {
      _items[veg.name]!.incrementQuantity();
    } else {
      _items[veg.name] = CartItem(vegetable: veg);
    }
    notifyListeners();
  }

  void removeOneFromCart(Vegetable veg) {
    if (_items.containsKey(veg.name)) {
      final CartItem cartItem = _items[veg.name]!;
      if (cartItem.quantity > 1) {
        cartItem.decrementQuantity();
      } else {
        _items.remove(veg.name);
      }
      notifyListeners();
    }
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}

class OrderHistoryModel extends ChangeNotifier {
  final String baseUrl; // 'https://freshvegorder.duckdns.org/api';
  final List<OrderSummary> _orderHistory = [];

  List<OrderSummary> get orderHistory => List.unmodifiable(_orderHistory);

  OrderHistoryModel({required this.baseUrl});

  void addOrder(OrderSummary order) {
    _orderHistory.insert(0, order); // เพิ่มออเดอร์ใหม่ไว้บนสุด
    notifyListeners();
  }

  /// โหลดประวัติการสั่งซื้อจาก backend
  Future<void> fetchOrderHistory(AuthService authService) async {
    final token = authService.token;
    if (token == null || token.isEmpty) {
      throw Exception("Token ยังไม่ได้ถูกกำหนด หรือหมดอายุ ต้องล็อกอินก่อน");
    }

    final int? userId = authService.userId;
    if (userId == null) {
      throw Exception("User ID is null, please login first");
    }

    final Uri url = Uri.parse('$baseUrl/orders/user/$userId/simple');

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        final List<OrderSummary> fetchedOrders = data.map((json) {
          final List<OrderedVegetable>
          items = (json['items'] as List? ?? []).map((item) {
            final veg = Vegetable(
              item['productId'] ?? 0,
              null, // imageUrl is null in order history
              name: item['name'] ?? 'Unknown', // ถ้าไม่มี name ให้ใช้ 'Unknown'
              price: (item['price'] ?? 0).toDouble(),
            );
            return OrderedVegetable(
              vegetable: veg,
              quantity:
                  (item['quantity'] as num?)?.toDouble() ??
                  0.0, // num -> double
            );
          }).toList();

          return OrderSummary(
            items: items,
            originalTotalAmount: (json['originalTotal'] ?? 0).toDouble(),
            discountValue: (json['discount'] ?? 0).toDouble(),
            finalTotalAmount: (json['finalTotal'] ?? 0)
                .toDouble(), // ✅ ใช้ finalTotal
            orderDate:
                DateTime.parse(json['createdAt'] ?? '') ?? DateTime.now(),
          );
        }).toList();

        _orderHistory
          ..clear()
          ..addAll(fetchedOrders);

        notifyListeners();
      } else {
        throw HttpStatusException(
          statusCode: response.statusCode,
          message: 'โหลดประวัติการสั่งซื้อไม่สำเร็จ',
        );
      }
    } catch (e) {
      throw Exception("เกิดข้อผิดพลาดในการโหลด order history: $e");
    }
  }
}

// Custom exception for HTTP status errors
class HttpStatusException implements Exception {
  final int statusCode;
  final String message;

  HttpStatusException({required this.statusCode, required this.message});

  @override
  String toString() => 'HttpStatusException: $message';
}

class VegetableService {
  final String jwtToken;

  // รับ token จาก login
  VegetableService({required this.jwtToken});

  Future<List<Vegetable>> fetchVegetables() async {
    final Uri url = Uri.parse(
      'https://freshvegorder.duckdns.org/api/products/online',
    );

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $jwtToken',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        return data
            .map<Vegetable>(
              (dynamic jsonItem) =>
                  Vegetable.fromJson(jsonItem as Map<String, dynamic>),
            )
            .toList();
      } else {
        throw HttpStatusException(
          statusCode: response.statusCode,
          message: 'Server responded with status ${response.statusCode}',
        );
      }
    } on http.ClientException {
      rethrow;
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }
}

class VegetableShopApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<CartModel>(
          create: (BuildContext context) => CartModel(),
        ),
        ChangeNotifierProvider<OrderHistoryModel>(
          create: (BuildContext context) => OrderHistoryModel(
            baseUrl: 'https://freshvegorder.duckdns.org/api',
            // You may replace '' with a valid token if available
          ),
        ),
      ],
      builder: (BuildContext context, Widget? child) {
        return MaterialApp(
          title: 'ร้านผัก',
          theme: ThemeData(
            primarySwatch: Colors.green,
            visualDensity: VisualDensity.adaptivePlatformDensity,
          ),
          home: VegetableShopPage(),
        );
      },
    );
  }
}

class VegetableShopPage extends StatefulWidget {
  @override
  _VegetableShopPageState createState() => _VegetableShopPageState();
}

class _VegetableShopPageState extends State<VegetableShopPage> {
  late VegetableService _vegetableService;
  late Future<List<Vegetable>> _vegetablesFuture;

  @override
  void initState() {
    super.initState();
    requestPermissions();
    // รับ token จาก AuthService ที่ login แล้ว
    final authService = context.read<AuthService>();
    _vegetableService = VegetableService(jwtToken: authService.token!);

    _vegetablesFuture = _vegetableService.fetchVegetables();
  }

  void _retryFetchVegetables() {
    setState(() {
      _vegetablesFuture = _vegetableService.fetchVegetables();
    });
  }

  @override
  Widget build(BuildContext context) {
    final CartModel cartModel = context.watch<CartModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("ร้านผัก"),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => OrderHistoryPage(),
                ),
              );
            },
            tooltip: 'ประวัติการสั่งซื้อ',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: FutureBuilder<List<Vegetable>>(
              future: _vegetablesFuture,
              builder: (BuildContext context, AsyncSnapshot<List<Vegetable>> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  String errorMessage;
                  if (snapshot.error is http.ClientException) {
                    errorMessage =
                        'ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้: โปรดตรวจสอบการเชื่อมต่ออินเทอร์เน็ตของคุณ';
                  } else if (snapshot.error is HttpStatusException) {
                    final HttpStatusException httpError =
                        snapshot.error as HttpStatusException;
                    errorMessage =
                        'ไม่สามารถโหลดรายการผักได้: เซิร์ฟเวอร์มีปัญหา (${httpError.statusCode})';
                  } else if (snapshot.error is Exception) {
                    // For other generic Exceptions, try to get the message without the "Exception: " prefix
                    errorMessage =
                        'เกิดข้อผิดพลาดในการโหลดข้อมูล:\n${(snapshot.error as Exception).toString().replaceFirst('Exception: ', '')}';
                  } else {
                    // Fallback for any other type of error/object
                    errorMessage =
                        'เกิดข้อผิดพลาดที่ไม่คาดคิด: ${snapshot.error.toString()}';
                  }
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          errorMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _retryFetchVegetables,
                          icon: const Icon(Icons.refresh),
                          label: const Text('ลองอีกครั้ง'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  );
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('ไม่มีรายการผักให้แสดง'));
                } else {
                  return ListView.builder(
                    itemCount: snapshot.data!.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Vegetable vegetable = snapshot.data![index];
                      return VegetableListItem(vegetable: vegetable);
                    },
                  );
                }
              },
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 8.0,
              horizontal: 16.0,
            ),
            child: Row(
              children: const <Widget>[
                Icon(Icons.shopping_cart, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  "ตะกร้าสินค้า",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Expanded(
            child: cartModel.items.isEmpty
                ? const Center(
                    child: Text(
                      'ตะกร้าว่างเปล่า',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: cartModel.items.length,
                    itemBuilder: (BuildContext context, int index) {
                      final CartItem cartItem = cartModel.items[index];
                      return CartItemWidget(cartItem: cartItem);
                    },
                  ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text(
                      "ยอดรวมทั้งหมด:",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "${cartModel.originalTotalAmount.toStringAsFixed(2)} บาท", // Display as int
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: cartModel.hasDiscountApplied
                            ? Colors.grey
                            : Colors.green,
                        decoration: cartModel.hasDiscountApplied
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ],
                ),
                if (cartModel.hasDiscountApplied)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        const Text(
                          "ส่วนลด 10%:",
                          style: TextStyle(fontSize: 16, color: Colors.red),
                        ),
                        Text(
                          "- ${cartModel.discountValue.toStringAsFixed(2)} บาท",
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(
                    top: cartModel.hasDiscountApplied ? 8.0 : 0.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        cartModel.hasDiscountApplied
                            ? "ยอดสุทธิ:"
                            : "ยอดรวมทั้งหมด:",
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "${cartModel.finalTotalAmount.toStringAsFixed(2)} บาท",
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: cartModel.items.isEmpty
                        ? null // Disable button if cart is empty
                        : () {
                            final OrderSummary orderSummary =
                                OrderSummary.fromCartModel(cartModel);
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (BuildContext context) =>
                                    ReceiptPage(orderSummary: orderSummary),
                              ),
                            );
                          },
                    icon: const Icon(Icons.payment),
                    label: const Text("ชำระเงิน"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      textStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VegetableListItem extends StatelessWidget {
  final Vegetable vegetable;

  const VegetableListItem({Key? key, required this.vegetable})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    final CartModel cartModel = context.read<CartModel>();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ListTile(
        title: Text(vegetable.name, style: const TextStyle(fontSize: 16)),
        subtitle: Text(
          "ราคา ${vegetable.price.toStringAsFixed(2)} บาท", // Display as int
          style: const TextStyle(color: Colors.grey),
        ),
        trailing: ElevatedButton.icon(
          onPressed: () => cartModel.addToCart(vegetable),
          icon: const Icon(Icons.add_shopping_cart, size: 18),
          label: const Text("เพิ่ม"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
  }
}

class CartItemWidget extends StatelessWidget {
  final CartItem cartItem;

  const CartItemWidget({Key? key, required this.cartItem}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final CartModel cartModel = context.read<CartModel>();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ListTile(
        leading: const Icon(Icons.check_circle_outline, color: Colors.green),
        title: Text(
          "${cartItem.vegetable.name} x ${cartItem.quantity}",
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          "รวม ${cartItem.totalPrice.toStringAsFixed(2)} บาท", // Display as int
          style: const TextStyle(color: Colors.grey),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.remove_circle, color: Colors.red),
          onPressed: () {
            cartModel.removeOneFromCart(cartItem.vegetable);
          },
        ),
      ),
    );
  }
}

class ReceiptPage extends StatelessWidget {
  final OrderSummary orderSummary;

  const ReceiptPage({Key? key, required this.orderSummary}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final CartModel cartModel = context.read<CartModel>();
    final OrderHistoryModel orderHistoryModel = context
        .read<OrderHistoryModel>();
    final AuthService authService = context.read<AuthService>();
    final OrderService orderService = OrderService(authService);

    return Scaffold(
      appBar: AppBar(
        title: const Text("ใบเสร็จ"),
        automaticallyImplyLeading: false, // Don't show back button
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              "ขอบคุณสำหรับการสั่งซื้อ!",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "วันที่: ${orderSummary.orderDate.day}/${orderSummary.orderDate.month}/${orderSummary.orderDate.year} ${orderSummary.orderDate.hour}:${orderSummary.orderDate.minute.toString().padLeft(2, '0')}",
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            const Text(
              "รายการสินค้า:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: orderSummary.items.length,
                itemBuilder: (BuildContext context, int index) {
                  final OrderedVegetable item = orderSummary.items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          "${item.vegetable.name} x ${item.quantity}",
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          "${item.itemTotalPrice.toStringAsFixed(2)} บาท",
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  const Text(
                    "ยอดรวมทั้งหมด:",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "${orderSummary.originalTotalAmount.toStringAsFixed(2)} บาท",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: orderSummary.discountValue > 0
                          ? Colors.grey
                          : Colors.green,
                      decoration: orderSummary.discountValue > 0
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            if (orderSummary.discountValue > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text(
                      "ส่วนลด 10%:",
                      style: TextStyle(fontSize: 16, color: Colors.red),
                    ),
                    Text(
                      "- ${orderSummary.discountValue.toStringAsFixed(2)} บาท",
                      style: const TextStyle(fontSize: 16, color: Colors.red),
                    ),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  orderSummary.discountValue > 0
                      ? "ยอดสุทธิ:"
                      : "ยอดรวมทั้งหมด:",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "${orderSummary.finalTotalAmount.toStringAsFixed(2)} บาท",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Center(
              child: ElevatedButton.icon(
                onPressed: () async {
                  try {
                    final success = await orderService.sendOrder(orderSummary);

                    if (success) {
                      orderHistoryModel.addOrder(orderSummary);
                      cartModel.clearCart();

                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => VegetableShopPage()),
                        (route) => false,
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("❌ ส่งออเดอร์ไม่สำเร็จ")),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("เกิดข้อผิดพลาด: $e")),
                    );
                  }
                },
                icon: const Icon(Icons.home),
                label: const Text("ส่งออเดอร์และกลับไปหน้าหลัก"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 15,
                  ),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OrderHistoryPage extends StatefulWidget {
  @override
  _OrderHistoryPageState createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final orderHistoryModel = Provider.of<OrderHistoryModel>(
        context,
        listen: false,
      );
      final authService = Provider.of<AuthService>(context, listen: false);
      orderHistoryModel.fetchOrderHistory(authService);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ประวัติการสั่งซื้อ")),
      body: Consumer<OrderHistoryModel>(
        builder:
            (
              BuildContext context,
              OrderHistoryModel orderHistoryModel,
              Widget? child,
            ) {
              if (orderHistoryModel.orderHistory.isEmpty) {
                return const Center(
                  child: Text(
                    'ไม่มีประวัติการสั่งซื้อ',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                );
              } else {
                return ListView.builder(
                  itemCount: orderHistoryModel.orderHistory.length,
                  itemBuilder: (BuildContext context, int index) {
                    final OrderSummary order =
                        orderHistoryModel.orderHistory[index];
                    final DateFormat formatter = DateFormat('dd/MM/yyyy HH:mm');
                    final String formattedDate = formatter.format(
                      order.orderDate,
                    );
                    final int totalItems = order.items.fold<int>(
                      0,
                      (int sum, OrderedVegetable item) =>
                          sum + item.quantity.toInt(),
                    );

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text(
                                  "สั่งซื้อเมื่อ: $formattedDate",
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  "${order.finalTotalAmount.toStringAsFixed(2)} บาท",
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "รายการสินค้า: $totalItems ชิ้น",
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            if (order.discountValue > 0)
                              const Text(
                                "มีส่วนลด",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.red,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }
            },
      ),
    );
  }
}

extension on OrderHistoryModel {
  FutureOr<dynamic> fetchOrderHistory() {}
}

class AuthService {
  String? _token;
  String? _companyId;
  String? _username;
  int? _userId;
  String? _role;

  String? get token => _token;
  String? get companyId => _companyId;
  String? get username => _username;
  int? get userId => _userId;
  String? get role => _role;

  /// Login ส่ง username@COMP001 + password
  Future<bool> login(String username, String password) async {
    final Uri url = Uri.parse(
      'https://freshvegorder.duckdns.org/api/auth/login',
    );

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);

      _token = data['token'];
      _username = data['username']; // user@COMP001
      _companyId = data['companyId']; // COMP001
      _userId = data['userId']; // ✅ backend ต้องส่งมาด้วย
      _role = data['role']; // ROLE_USER

      // ยังติด error import SharedPreferences
      // ✅ เก็บลง SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', _token!);
      await prefs.setString('username', _username!);
      await prefs.setString('companyId', _companyId!);
      await prefs.setInt('userId', _userId!);
      await prefs.setString('role', _role!);

      return true;
    } else {
      print('Login failed: ${response.body}');
      return false;
    }
  }

  void logout() {
    _token = null;
    _username = null;
    _companyId = null;
    _userId = null;
    _role = null;
  }

  /// Check if logged in
  bool get isLoggedIn => _token != null;
}

class OrderService {
  final AuthService authService;

  OrderService(this.authService);

  Future<bool> sendOrder(OrderSummary order) async {
    final token = authService.token;
    if (token == null) {
      throw Exception("ยังไม่ได้ล็อกอิน หรือ token หมดอายุ");
    }

    final Uri url = Uri.parse('https://freshvegorder.duckdns.org/api/orders');

    // คำนวณยอดสุทธิรวมส่วนลด
    final double finalTotal = double.parse(
      (order.originalTotalAmount - order.discountValue).toStringAsFixed(2),
    );

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        // ✅ companyId อาจไม่ต้องส่ง ถ้า backend ดึงจาก JWT แล้ว
        'userId': authService.userId, // ✅ ต้องเก็บ userId หลัง login
        'companyId': authService.companyId,
        'customerName': authService.username, // ✅ เพิ่มบรรทัดนี้
        'items': order.items
            .map(
              (e) => {
                'productId': e.vegetable.id,
                'quantity': e.quantity,
                // 'unit': e.vegetable.unit, // ✅ ตัดออกชั่วคราว
                'price': double.parse(
                  e.vegetable.price.toStringAsFixed(2),
                ), // ส่ง Double 2 หลัก
              },
            )
            .toList(),
        // 'totalAmount': order.finalTotalAmount,
        'totalAmount': finalTotal, // ส่ง Double 2 หลักรวมส่วนลดแล้ว
        'originalTotal': double.parse(
          order.originalTotalAmount.toStringAsFixed(2),
        ), // ยอดรวมก่อนลด
        'discount': double.parse(
          order.discountValue.toStringAsFixed(2),
        ), // ส่วนลด
        'finalTotal': double.parse(
          (order.originalTotalAmount - order.discountValue).toStringAsFixed(2),
        ), // ยอดสุทธิ
        'orderDate': order.orderDate.toIso8601String(),
      }),
    );

    // ✅ ยอมรับทั้ง 200 OK และ 201 CREATED
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return true;
    } else {
      throw HttpStatusException(
        statusCode: response.statusCode,
        message: 'สั่งซื้อไม่สำเร็จ: ${response.body}',
      );
    }
  }
}

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      appBar: AppBar(title: const Text("เข้าสู่ระบบ")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: "Username"),
            ),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password"),
            ),
            const SizedBox(height: 20),
            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _loading
                  ? null
                  : () async {
                      setState(() => _loading = true);
                      final success = await authService.login(
                        _usernameController.text,
                        _passwordController.text,
                      );
                      setState(() => _loading = false);

                      if (success) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => VegetableShopPage(),
                          ),
                        );
                      } else {
                        setState(
                          () => _errorMessage =
                              "เข้าสู่ระบบไม่สำเร็จ โปรดลองอีกครั้ง",
                        );
                      }
                    },
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text("เข้าสู่ระบบ"),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> main() async {
  // runApp(VegetableShopApp());

  // เรียก Flutter binding ก่อน
  WidgetsFlutterBinding.ensureInitialized();

  // Request permission ก่อนเริ่มแอป
  await requestPermissions();

  // สร้าง AuthService ก่อน เพื่อใช้ token
  final authService = AuthService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<CartModel>(create: (_) => CartModel()),
        ChangeNotifierProvider<OrderHistoryModel>(
          create: (_) => OrderHistoryModel(
            baseUrl: 'https://freshvegorder.duckdns.org/api',
            // ใช้ token จาก authService ถ้ามี
          ),
        ),
        Provider<AuthService>(create: (_) => authService),
      ],
      child: MaterialApp(home: LoginPage()),
    ),
  );
}

// Define the missing requestPermissions function
Future<void> requestPermissions() async {
  await Permission.storage.request();
  var status = await Permission.camera.status;
  if (!status.isGranted) {
    await Permission.camera.request();
  }
  // await Permission.camera.request();
  // Add more permissions if needed
}
