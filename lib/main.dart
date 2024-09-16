import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Captcha Solver',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: CaptchaSolver(),
    );
  }
}

class CaptchaSolver extends StatefulWidget {
  @override
  _CaptchaSolverState createState() => _CaptchaSolverState();
}

class _CaptchaSolverState extends State<CaptchaSolver> {
  final picker = ImagePicker();
  List<File> backgroundImages = [];
  Map<String, dynamic> accounts = {};
  String captchaSolution = "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Captcha Solver"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: _addAccount,
              child: Text('Add Account'),
            ),
            ElevatedButton(
              onPressed: _uploadBackgrounds,
              child: Text('Upload Backgrounds'),
            ),
            if (captchaSolution.isNotEmpty)
              Text("Captcha Solved: $captchaSolution"),
          ],
        ),
      ),
    );
  }

  // إضافة حساب جديد
  Future<void> _addAccount() async {
    String username = await _inputDialog("Enter Username");
    String password = await _inputDialog("Enter Password", obscureText: true);

    if (username != null && password != null) {
      // إرسال طلب تسجيل الدخول
      bool success = await _login(username, password);
      if (success) {
        setState(() {
          accounts[username] = {
            'password': password,
            'session': http.Client(), // حفظ الجلسة هنا لكل مستخدم
            'captcha_id1': null,
            'captcha_id2': null,
          };
        });
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Login Failed')));
      }
    }
  }

  // نافذة إدخال بسيطة
  Future<String> _inputDialog(String label, {bool obscureText = false}) async {
    TextEditingController controller = TextEditingController();
    String inputValue = "";
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          obscureText: obscureText,
          decoration: InputDecoration(hintText: label),
        ),
        actions: [
          ElevatedButton(
            child: Text('OK'),
            onPressed: () {
              inputValue = controller.text;
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
    return inputValue;
  }

  // رفع الصور الخلفية
  Future<void> _uploadBackgrounds() async {
    final pickedFiles = await picker.pickMultiImage();
    if (pickedFiles != null) {
      setState(() {
        backgroundImages = pickedFiles.map((file) => File(file.path)).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${backgroundImages.length} images uploaded!")));
    }
  }

  // تسجيل الدخول إلى API
  Future<bool> _login(String username, String password) async {
    const String loginUrl = 'https://api.ecsc.gov.sy:8080/secure/auth/login';
    Map<String, String> headers = _generateHeaders();
    Map<String, String> loginData = {
      'username': username,
      'password': password,
    };

    try {
      final response = await http.post(Uri.parse(loginUrl),
          headers: headers, body: jsonEncode(loginData));

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Login Successful')));
        return true;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Login Failed: ${response.statusCode} ${response.body}')));
        return false;
      }
    } catch (e) {
      print("Login error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login Failed: Network Error')));
      return false;
    }
  }

  // استرجاع الكابتشا
  Future<void> _requestCaptcha(String username, String captchaId) async {
    var session = accounts[username]['session'];
    final response = await session.get(
        Uri.parse('https://api.ecsc.gov.sy:8080/files/fs/captcha/$captchaId'),
        headers: _generateHeaders());

    if (response.statusCode == 200) {
      final captchaData = jsonDecode(response.body)['file'];
      if (captchaData != null) {
        File captchaImage = await _saveBase64Image(captchaData);
        File processedImage = await _processCaptchaBackground(captchaImage);
        String solvedCaptcha = await _solveCaptcha(processedImage);
        await _submitCaptcha(username, captchaId, solvedCaptcha);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Failed to retrieve captcha: ${response.statusCode}")));
    }
  }

  // حل الكابتشا
  Future<String> _solveCaptcha(File captchaImage) async {
    // هنا من المفترض استخدام مكتبة OCR مثل EasyOCR، لكن في Flutter قد تكون مختلفة
    // ستحتاج إلى مكتبة مثل `google_ml_kit` أو `mkt_ocr` لقراءة النص من الصورة.
    // Placeholder لتوضيح الطريقة فقط
    String ocrResult = "OCR Placeholder Result";
    return _processCaptchaText(ocrResult);
  }

  // تحليل النص من OCR واستخراج العملية الرياضية
  String _processCaptchaText(String ocrText) {
    RegExp regExp = RegExp(r'(\d+)\s*([+*xX-])\s*(\d+)');
    Match match = regExp.firstMatch(ocrText);
    if (match != null) {
      int num1 = int.parse(match.group(1));
      String operator = match.group(2);
      int num2 = int.parse(match.group(3));

      switch (operator) {
        case '+':
          return (num1 + num2).toString();
        case '-':
          return (num1 - num2).toString();
        case '*':
        case 'x':
        case 'X':
          return (num1 * num2).toString();
        default:
          return "Error";
      }
    }
    return "Invalid Captcha";
  }

  // إرسال الحل النهائي للكابتشا إلى السيرفر
  Future<void> _submitCaptcha(String username, String captchaId, String captchaSolution) async {
    var session = accounts[username]['session']; // استخدام الجلسة المحفوظة
    String submitUrl = 'https://api.ecsc.gov.sy:8080/rs/reserve?id=$captchaId&captcha=$captchaSolution';
    Map<String, String> headers = _generateHeaders();

    try {
      final response = await session.get(Uri.parse(submitUrl), headers: headers);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Captcha submitted successfully!')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to submit captcha: ${response.statusCode} ${response.body}')));
      }
    } catch (e) {
      print("Submit captcha error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Submit Captcha Failed: Network Error')));
    }
  }

  // حفظ الصورة من Base64 إلى ملف
  Future<File> _saveBase64Image(String base64Str) async {
    Uint8List imageBytes = base64Decode(base64Str);
    String dir = (await getTemporaryDirectory()).path;
    File file = File('$dir/captcha.jpg');
    await file.writeAsBytes(imageBytes);
    return file;
  }

  // معالجة الخلفية للصورة
  Future<File> _processCaptchaBackground(File captchaImage) async {
    img.Image captcha = img.decodeImage(captchaImage.readAsBytesSync());

    if (backgroundImages.isNotEmpty) {
      img.Image bestBackground;
      int minDiff = 999999999;

      for (File backgroundFile in backgroundImages) {
        img.Image background = img.decodeImage(backgroundFile.readAsBytesSync());
        background = img.copyResize(background, width: captcha.width, height: captcha.height);

        int diff = _calculateImageDifference(captcha, background);
        if (diff < minDiff) {
          minDiff = diff;
          bestBackground = background;
        }
      }

      if (bestBackground != null) {
        captcha = _removeBackground(captcha, bestBackground);
      }
    }

    String dir = (await getTemporaryDirectory()).path;
    File processedFile = File('$dir/processed_captcha.jpg');
    processedFile.writeAsBytesSync(img.encodeJpg(captcha));
    return processedFile;
  }

  // حساب الفرق بين الصور
  int _calculateImageDifference(img.Image img1, img.Image img2) {
    int diff = 0;
    for (int y = 0; y < img1.height; y++) {
      for (int x = 0; x < img1.width; x++) {
        int pixel1 = img1.getPixel(x, y);
        int pixel2 = img2.getPixel(x, y);
        diff += (img.getRed(pixel1) - img.getRed(pixel2)).abs() +
            (img.getGreen(pixel1) - img.getGreen(pixel2)).abs() +
            (img.getBlue(pixel1) - img.getBlue(pixel2)).abs();
      }
    }
    return diff;
  }

  // إزالة الخلفية من الكابتشا
  img.Image _removeBackground(img.Image captcha, img.Image background) {
    img.Image result = img.Image(captcha.width, captcha.height);

    for (int y = 0; y < captcha.height; y++) {
      for (int x = 0; x < captcha.width; x++) {
        int pixelCaptcha = captcha.getPixel(x, y);
        int pixelBackground = background.getPixel(x, y);
        if ((img.getRed(pixelCaptcha) - img.getRed(pixelBackground)).abs() > 30 ||
            (img.getGreen(pixelCaptcha) - img.getGreen(pixelBackground)).abs() > 30 ||
            (img.getBlue(pixelCaptcha) - img.getBlue(pixelBackground)).abs() > 30) {
          result.setPixel(x, y, pixelCaptcha);
        } else {
          result.setPixel(x, y, img.getColor(255, 255, 255));
        }
      }
    }

    return result;
  }

  // توليد الهيدرز مع User Agent عشوائي
  Map<String, String> _generateHeaders() {
    List<String> userAgentList = [
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv=89.0) Gecko/20100101 Firefox/89.0",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.1.1 Safari/605.1.15",
      "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/56.0.2924.87 Safari/537.36",
      "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/47.0.2526.106 Safari/537.36",
      "Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2228.0 Safari/537.36"
    ];
    String randomUserAgent = userAgentList[DateTime.now().millisecond % userAgentList.length];

    return {
      'User-Agent': randomUserAgent,
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/plain, */*',
      'Referer': 'https://ecsc.gov.sy/',
      'Origin': 'https://ecsc.gov.sy',
      'Connection': 'keep-alive',
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'same-site'
    };
  }
}
