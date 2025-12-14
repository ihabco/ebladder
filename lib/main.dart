import 'dart:async'; // Add this import
import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'home_page.dart'; // Import the home page

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ebladder',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool showText = false;

  @override
  void initState() {
    super.initState();

    // Scale Animation Controller
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _scaleAnimation =
        Tween<double>(begin: 0.1, end: 1).animate(
          CurvedAnimation(parent: _controller, curve: Curves.elasticInOut),
        )..addListener(() {
          setState(() {});
        });

    // Start animation
    _controller.forward();

    // Show text after scale animation
    Timer(const Duration(seconds: 1), () {
      setState(() {
        showText = true;
      });
    });

    // Navigate to home page after 4 seconds
    Timer(const Duration(seconds: 4), () {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated Image
            ScaleTransition(
              scale: _scaleAnimation,
              child: Image.asset(
                'assets/logo.png', // Make sure to add your logo to assets
                width: 300,
                height: 300,
              ),
            ),

            const SizedBox(height: 10),

            // Animated Text
            if (showText)
              DefaultTextStyle(
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  //color: Colors.blueAccent,
                  color: Color(0xFF002DB2),
                ),
                child: AnimatedTextKit(
                  totalRepeatCount: 1,
                  animatedTexts: [TyperAnimatedText('Ebladder ... Easy Life')],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
