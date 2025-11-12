import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// 1. CartItem model
class CartItem {
  final String id;
  final String name;
  final double price;
  int quantity;

  CartItem({
    required this.id,
    required this.name,
    required this.price,
    this.quantity = 1,
  });

  // Convert CartItem to a Map for Firestore
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'quantity': quantity,
    };
  }

  // Create a CartItem from a Map from Firestore
  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'],
      name: json['name'],
      price: json['price'] is int ? (json['price'] as int).toDouble() : json['price'],
      quantity: json['quantity'],
    );
  }
}

// 2. CartProvider
class CartProvider with ChangeNotifier {
  List<CartItem> _items = [];
  String? _userId;
  StreamSubscription? _authSubscription;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<CartItem> get items => _items;

  // Constructor
  CartProvider() {
    print('CartProvider created.');
  }

  // Initialize the auth listener
  void initializeAuthListener() {
    print('CartProvider auth listener initialized');
    _authSubscription = _auth.authStateChanges().listen((User? user) {
      if (user == null) {
        // User is logged out
        print('User logged out, clearing cart.');
        _userId = null;
        _items = []; // Clear local cart
      } else {
        // User is logged in
        print('User logged in: ${user.uid}. Fetching cart...');
        _userId = user.uid;
        _fetchCart();
      }
      notifyListeners();
    });
  }

  double get subtotal {
    double total = 0.0;
    for (var item in _items) {
      total += (item.price * item.quantity);
    }
    return total;
  }

  double get vat {
    return subtotal * 0.12; // 12% of the subtotal
  }
  
  double get totalPriceWithVat {
    return subtotal + vat;
  }
  
  double get totalPrice => totalPriceWithVat;

  int get itemCount {
    var total = 0;
    for (var item in _items) total += item.quantity;
    return total;
  }

  // Fetches the cart from Firestore
  Future<void> _fetchCart() async {
    if (_userId == null) return; // Not logged in, nothing to fetch

    try {
      // 1. Get the user's specific cart document
      final doc = await _firestore.collection('userCarts').doc(_userId).get();
      
      if (doc.exists && doc.data()?['cartItems'] != null) {
        // 2. Get the list of items from the document
        final List<dynamic> cartData = doc.data()!['cartItems'];
        
        // 3. Convert that list of Maps into our List<CartItem>
        _items = cartData.map((item) => CartItem.fromJson(Map<String, dynamic>.from(item))).toList();
        print('Cart fetched successfully: ${_items.length} items');
      } else {
        // 4. The user has no saved cart, start with an empty one
        _items = [];
      }
    } catch (e) {
      print('Error fetching cart: $e');
      _items = []; // On error, default to an empty cart
    }
    notifyListeners(); // Update the UI
  }

  // Saves the current local cart to Firestore
  Future<void> _saveCart() async {
    if (_userId == null) return; // Not logged in, nowhere to save

    try {
      // 1. Convert our List<CartItem> into a List<Map>
      final List<Map<String, dynamic>> cartData = 
          _items.map((item) => item.toJson()).toList();
      
      // 2. Find the user's document and set the 'cartItems' field
      await _firestore.collection('userCarts').doc(_userId).set({
        'cartItems': cartData,
      });
      print('Cart saved to Firestore');
    } catch (e) {
      print('Error saving cart: $e');
    }
  }

  void addItem(String id, String name, double price, [int quantity = 1]) {
    final index = _items.indexWhere((it) => it.id == id);
    if (index != -1) {
      _items[index].quantity += quantity;
    } else {
      _items.add(CartItem(
        id: id,
        name: name,
        price: price,
        quantity: quantity,
      ));
    }
    _saveCart(); // Save to Firestore
    notifyListeners();
  }

  void removeItem(String id) {
    _items.removeWhere((it) => it.id == id);
    _saveCart(); // Save to Firestore
    notifyListeners();
  }

  // Creates an order in the 'orders' collection
  Future<void> placeOrder() async {
    if (_userId == null || _items.isEmpty) {
      throw Exception('Cart is empty or user is not logged in.');
    }

    try {
      final List<Map<String, dynamic>> cartData = 
          _items.map((item) => item.toJson()).toList();
      
      // Get all our new calculated values
      final double sub = subtotal;
      final double v = vat;
      final double total = totalPriceWithVat;
      final int count = itemCount;

      // Add debug prints to verify data
      print('Placing order with userID: $_userId');
      print('Order subtotal: $sub, VAT: $v, Total: $total, Item count: $count');
      print('Order items: $cartData');
      
      final orderRef = await _firestore.collection('orders').add({
        'userID': _userId,
        'items': cartData,
        'subtotal': sub,
        'vat': v,
        'totalPrice': total,
        'itemCount': count,
        'status': 'Pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      print('Order placed successfully with ID: ${orderRef.id}');
      
      // Clear the cart after successful order placement
      _items = [];
      await _saveCart();
    } catch (e) {
      print('Error placing order: $e');
      rethrow;
    }
  }

  // Clears the cart both locally and in Firestore
  Future<void> clearCart() async {
    _items = [];
    
    if (_userId != null) {
      try {
        await _firestore.collection('userCarts').doc(_userId).set({
          'cartItems': [],
        });
        print('Firestore cart cleared.');
      } catch (e) {
        print('Error clearing Firestore cart: $e');
      }
    }
    
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel(); // Cancel the auth listener
    super.dispose();
  }
}