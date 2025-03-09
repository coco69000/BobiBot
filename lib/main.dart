// Fichier principal : main.dart
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import 'firebase_options.dart';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:permission_handler/permission_handler.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialiser OneSignal
  await initOneSignal();

  runApp(const MyApp());
}

Future<void> initOneSignal() async {
  // Demander les permissions de notification
  await OneSignal.shared.promptUserForPushNotificationPermission();

  // Activer les journaux de débogage
  OneSignal.shared.setLogLevel(OSLogLevel.verbose, OSLogLevel.none);

  // Initialiser OneSignal avec l'App ID
  await OneSignal.shared.setAppId("2e1be2be-5ff4-452f-8a92-47af18efd042");

  // Récupérer le Player ID de l'utilisateur
  OneSignal.shared.setPermissionObserver((OSPermissionStateChanges changes) {
    if (changes.to.hasPrompted) {
      OneSignal.shared.getDeviceState().then((deviceState) {
        final playerId = deviceState?.userId;
        if (playerId != null) {
          print("Player ID: $playerId");
          // Stocker le Player ID dans Firestore
          _storePlayerId(playerId);
        } else {
          print("Player ID non trouvé après l'initialisation de OneSignal.");
        }
      });
    }
  });
}

Future<void> _storePlayerId(String playerId) async {
  try {
    final user = FirebaseAuth.instance.currentUser ;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'oneSignalPlayerId': playerId, // Assurez-vous d'utiliser le bon champ
      }, SetOptions(merge: true)); // Utilisez merge pour éviter d'écraser d'autres données
      print("Player ID enregistré avec succès pour l'utilisateur ${user.uid}");
    } else {
      print("Aucun utilisateur connecté");
    }
  } catch (e) {
    print("Erreur lors de la sauvegarde du Player ID: $e");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Assistant IA',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const AuthWrapper(),
    );
  }
}

// Wrapper pour gérer l'état d'authentification
// Wrapper pour gérer l'état d'authentification
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    // Attendre pour vérifier l'état d'authentification
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _buildLoadingScreen();
    }

    return StreamBuilder<User?>(
      stream: _auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          User? user = snapshot.data;
          if (user == null) {
            return const LoginScreen();
          } else {
            // Vérifier et mettre à jour le Player ID après la connexion
            _checkAndUpdatePlayerId(user);
            return ChatScreen(userId: user.uid);
          }
        }
        return _buildLoadingScreen();
      },
    );
  }

  Future<void> _checkAndUpdatePlayerId(User user) async {
    try {
      final deviceState = await OneSignal.shared.getDeviceState();
      if (deviceState?.userId != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'oneSignalPlayerId': deviceState!.userId!,
        }, SetOptions(merge: true));
        print("Player ID mis à jour pour ${user.uid}");
      }
    } catch (e) {
      print("Erreur lors de la mise à jour du Player ID: $e");
    }
  }
  Widget _buildLoadingScreen() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Chargement...'),
          ],
        ),
      ),
    );
  }
}

// Écran de connexion
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = false;
  bool _isLogin = true; // true pour connexion, false pour inscription
  String _errorMessage = '';

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      try {
        User? user;

        if (_isLogin) {
          // Connexion
          final userCredential = await _auth.signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
          user = userCredential.user;
        } else {
          // Inscription
          final userCredential = await _auth.createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
          user = userCredential.user;

          // Créer le document utilisateur dans Firestore
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user!.uid)
              .set({
            'email': _emailController.text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
            'lastActive': FieldValue.serverTimestamp(),
          });
        }

        // Récupérer le Player ID après l'authentification
        if (user != null) {
          final deviceState = await OneSignal.shared.getDeviceState();
          if (deviceState?.userId != null) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .set({
              'oneSignalPlayerId': deviceState!.userId!,
            }, SetOptions(merge: true));
            print("Player ID enregistré avec succès");
          }
        }

      } on FirebaseAuthException {
        // Gestion des erreurs existante...
      } catch (e) {
        // Gestion des erreurs existante...
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isLogin ? 'Connexion' : 'Inscription')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    'Assistant IA',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: 40),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Veuillez entrer votre email';
                    }
                    // Validation email basique
                    bool emailValid = RegExp(
                      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
                    ).hasMatch(value);
                    if (!emailValid) {
                      return 'Veuillez entrer un email valide';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Mot de passe',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Veuillez entrer votre mot de passe';
                    }
                    if (!_isLogin && value.length < 6) {
                      return 'Le mot de passe doit contenir au moins 6 caractères';
                    }
                    return null;
                  },
                ),
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child:
                  _isLoading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : Text(_isLogin ? 'Se connecter' : 'S\'inscrire'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed:
                  _isLoading
                      ? null
                      : () {
                    setState(() {
                      _isLogin = !_isLogin;
                      _errorMessage = '';
                    });
                  },
                  child: Text(
                    _isLogin
                        ? 'Pas de compte ? S\'inscrire'
                        : 'Déjà un compte ? Se connecter',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
// Écran principal de chat
class ChatScreen extends StatefulWidget {
  final String userId;

  const ChatScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final String _apiKey =
      "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"; // Remplacez par votre clé API Claude
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = false;
  bool _isInitialized = false;
  double _emotionalHealth = 100.0;
  int _negativeMessageCount = 0;
  int _positiveMessageCount = 0;
  String _currentPersonality = "";
  List<Map<String, dynamic>> _scheduledNotifications = [];

  @override
  void initState() {
    super.initState();
    _initializeChat();
    _loadEmotionalHealth();
    _loadScheduledNotifications(); // Charger les notifications planifiées
  }


  Future<void> initOneSignal() async {
    // Demander les permissions de notification
    await requestNotificationPermission(context);

    // Initialiser OneSignal
    OneSignal.shared.setAppId("2e1be2be-5ff4-452f-8a92-47af18efd042");

    // Récupérer le Player ID de l'utilisateur
    OneSignal.shared.setPermissionObserver((OSPermissionStateChanges changes) {
      if (changes.to.hasPrompted) {
        OneSignal.shared.getDeviceState().then((deviceState) {
          final playerId = deviceState?.userId;
          if (playerId != null) {
            print("Player ID: $playerId");
            // Stocker le Player ID dans Firestore
            _storePlayerId(playerId);
          }
        });
      }
    });

    // Gérer les notifications en premier plan
    OneSignal.shared.setNotificationWillShowInForegroundHandler((OSNotificationReceivedEvent event) {
      event.complete(event.notification);
    });

    // Gérer l'ouverture des notifications
    OneSignal.shared.setNotificationOpenedHandler((OSNotificationOpenedResult result) {
      // Gérer l'ouverture de la notification
    });
  }

  Future<void> _storePlayerId(String playerId) async {
    try {
      final user = FirebaseAuth.instance.currentUser ;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'oneSignalPlayerId': playerId, // Assurez-vous d'utiliser le bon champ
        }, SetOptions(merge: true)); // Utilisez merge pour éviter d'écraser d'autres données
        print("Player ID enregistré avec succès pour l'utilisateur ${user.uid}");
      } else {
        print("Aucun utilisateur connecté");
      }
    } catch (e) {
      print("Erreur lors de la sauvegarde du Player ID: $e");
    }
  }

  Future<void> _showScheduledNotificationsDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Notifications planifiées'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _scheduledNotifications.isEmpty
                  ? [const Text('Aucune notification planifiée.')]
                  : _scheduledNotifications.map((notification) {
                final sendTime = DateFormat('yyyy-MM-dd – kk:mm').format(notification['sendTime']);
                return ListTile(
                  title: Text('• ${notification['message']}'),
                  subtitle: Text('Envoyée à: $sendTime'),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _editNotificationDate(context, notification),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editNotificationDate(BuildContext context, Map<String, dynamic> notification) async {
    // Afficher un sélecteur de date
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: notification['sendTime'],
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );

    if (pickedDate != null) {
      // Afficher un sélecteur d'heure
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(notification['sendTime']),
      );

      if (pickedTime != null) {
        // Combiner la date et l'heure
        final newSendTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        // Mettre à jour la notification dans la liste locale
        setState(() {
          notification['sendTime'] = newSendTime;
        });

        // Mettre à jour la notification dans Firestore
        await _updateNotificationInFirestore(notification);

        // Reprogrammer la notification avec OneSignal
        await _rescheduleNotificationWithOneSignal(notification);

        // Rafraîchir la boîte de dialogue
        if (mounted) { // Utiliser `mounted` depuis l'état du widget
          Navigator.of(context).pop();
          _showScheduledNotificationsDialog(context);
        }
      }
    }
  }

  Future<void> _updateNotificationInFirestore(Map<String, dynamic> notification) async {
    try {
      // Récupérer la liste actuelle des notifications
      final userDoc = await _firestore.collection('users').doc(widget.userId).get();
      final List<dynamic> notifications = userDoc.data()!['scheduledNotifications'];

      // Trouver et mettre à jour la notification correspondante
      final updatedNotifications = notifications.map((n) {
        if (n['message'] == notification['message']) {
          return {
            'message': notification['message'],
            'sendTime': notification['sendTime'].toIso8601String(),
            'score': notification['score'], // Inclure le score

          };
        }
        return n;
      }).toList();

      // Mettre à jour Firestore
      await _firestore.collection('users').doc(widget.userId).update({
        'scheduledNotifications': updatedNotifications,
      });
    } catch (e) {
      print("Erreur lors de la mise à jour de la notification dans Firestore: $e");
    }
  }

  Future<void> _rescheduleNotificationWithOneSignal(Map<String, dynamic> notification) async {
    try {
      // Récupérer le Player ID de l'utilisateur depuis Firestore
      final userDoc = await _firestore.collection('users').doc(widget.userId).get();
      final playerId = userDoc.data()?['oneSignalPlayerId'];

      if (playerId == null) {
        print("Player ID non trouvé");
        return;
      }

      // Convertir la date en UTC
      final sendTimeUtc = notification['sendTime'].toUtc();

      // Envoyer la requête à OneSignal
      final url = Uri.parse('https://onesignal.com/api/v1/notifications');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic os_v2_app_fyn6fps76rcs7cusi6xrr36qilhyntjd3fhegvnz3qbkqc2xyfqfdb56dnnzvrrfbuxmcsreli6qrjv5ukakrzhrwq2prhu2brwhaey',
        },
        body: jsonEncode({
          'app_id': '2e1be2be-5ff4-452f-8a92-47af18efd042',
          'contents': {'en': notification['message']},
          'include_player_ids': [playerId], // Utiliser le Player ID de l'utilisateur
          'send_after': sendTimeUtc.toIso8601String(), // Format ISO 8601 en UTC
        }),
      );

      // Vérifier la réponse
      if (response.statusCode == 200) {
        print("Notification reprogrammée avec succès");
      } else {
        print("Erreur lors de la reprogrammation de la notification: ${response.body}");
      }
    } catch (e) {
      print("Erreur lors de la reprogrammation de la notification: $e");
    }
  }
  Future<void> _scheduleNotification(String userMessage, int delayInMinutes) async {
    try {
      // Générer un contenu de notification personnalisé
      final notificationData = await _generateNotificationContent(userMessage, delayInMinutes);

      // Ajouter à la liste des notifications planifiées
      _scheduledNotifications.add(notificationData);

      // Sauvegarder dans Firestore
      await _firestore.collection('users').doc(widget.userId).update({
        'scheduledNotifications': FieldValue.arrayUnion([
          {
            'message': notificationData['message'],
            'sendTime': notificationData['sendTime'].toIso8601String(),
            'keywords': notificationData['keywords'],
            'score': 0,
          }
        ]),
      });

      // Planifier la notification avec OneSignal
      final userDoc = await _firestore.collection('users').doc(widget.userId).get();
      final playerId = userDoc.data()?['oneSignalPlayerId'];

      if (playerId == null) {
        print("Player ID non trouvé");
        return;
      }

      final url = Uri.parse('https://onesignal.com/api/v1/notifications');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic os_v2_app_fyn6fps76rcs7cusi6xrr36qilhyntjd3fhegvnz3qbkqc2xyfqfdb56dnnzvrrfbuxmcsreli6qrjv5ukakrzhrwq2prhu2brwhaey',
        },
        body: jsonEncode({
          'app_id': '2e1be2be-5ff4-452f-8a92-47af18efd042',
          'contents': {'en': notificationData['message']},
          'include_player_ids': [playerId],
          'send_after': notificationData['sendTime'].toUtc().toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        print("Notification planifiée avec succès: ${notificationData['message']}");
      } else {
        print("Erreur lors de la planification de la notification: ${response.body}");
      }
    } catch (e) {
      print("Erreur lors de la planification de la notification: $e");
    }
  }

// Méthode pour extraire des mots-clés d'un message
  List<String> _extractKeywords(String message) {
    try {
      // Éliminer les mots courts, articles, prépositions, etc.
      final stopWords = ['le', 'la', 'les', 'un', 'une', 'des', 'et', 'ou', 'mais', 'donc', 'car', 'pour', 'dans', 'sur', 'avec', 'sans', 'par'];

      // Diviser le message en mots, filtrer les mots significatifs
      final words = message.toLowerCase()
          .replaceAll(RegExp(r'[.,!?;:]'), '') // Supprimer la ponctuation
          .split(' ')
          .where((word) =>
      word.length > 3 && // Mots de plus de 3 lettres
          !stopWords.contains(word.toLowerCase()) && // Pas de mots vides
          !RegExp(r'^\d+$').hasMatch(word)) // Pas uniquement des chiffres
          .toList();

      // Limiter à 5 mots-clés maximum pour éviter le bruit
      return words.take(5).toList();
    } catch (e) {
      print("Erreur lors de l'extraction des mots-clés: $e");
      return [];
    }
  }

  // Fonction pour générer un message de notification personnalisé
  Future<Map<String, dynamic>> _generateNotificationContent(String userMessage, int delayInMinutes) async {
    try {
      final url = Uri.parse('https://api.anthropic.com/v1/messages');
      const systemPrompt = """
Analyse ce message et crée:
1. Un message de notification qui résume l'intention ou le sujet principal
2. Une liste de 3 à 5 mots-clés pertinents (noms communs, verbes, lieux, dates) qui aideront à retrouver cette notification

Format JSON uniquement:
{
  "notificationMessage": "Message concis et informatif pour la notification",
  "keywords": ["mot1", "mot2", "mot3"]
}
""";

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-3-haiku-20240307',
          'max_tokens': 150,
          'system': systemPrompt,
          'messages': [
            {'role': 'user', 'content': userMessage},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final analysisText = data['content'][0]['text'];

        // Extraire uniquement le JSON
        final cleanedText = analysisText
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();

        final analysis = jsonDecode(cleanedText);

        final sendTime = DateTime.now().add(Duration(minutes: delayInMinutes));

        return {
          'message': analysis['notificationMessage'],
          'sendTime': sendTime,
          'keywords': analysis['keywords'],
          'score': 0,
        };
      } else {
        // Fallback si l'API échoue
        final List<String> keywords = _extractKeywords(userMessage);
        final String fallbackMessage = "Rappel: ${userMessage.length > 30 ? userMessage.substring(0, 30) + '...' : userMessage}";

        final sendTime = DateTime.now().add(Duration(minutes: delayInMinutes));

        return {
          'message': fallbackMessage,
          'sendTime': sendTime,
          'keywords': keywords,
          'score': 0,
        };
      }
    } catch (e) {
      print("Erreur lors de la génération du contenu de notification: $e");

      // Fallback simple en cas d'erreur
      final List<String> keywords = _extractKeywords(userMessage);
      final sendTime = DateTime.now().add(Duration(minutes: delayInMinutes));

      return {
        'message': "Rappel important",
        'sendTime': sendTime,
        'keywords': keywords,
        'score': 0,
      };
    }
  }

  Future<void> _loadScheduledNotifications() async {
    try {
      final userDoc = await _firestore.collection('users').doc(widget.userId).get();
      if (userDoc.exists && userDoc.data()!.containsKey('scheduledNotifications')) {
        final notifications = userDoc.data()!['scheduledNotifications'] as List<dynamic>;
        _scheduledNotifications = notifications.map((notification) {
          return {
            'message': notification['message'],
            'sendTime': DateTime.parse(notification['sendTime']),
            'score': notification['score'] ?? 0, // Charger le score, initialiser à 0 si absent

          };
        }).toList();
      }
    } catch (e) {
      print("Erreur lors du chargement des notifications planifiées: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Impossible de charger les notifications planifiées."),
        ),
      );
    }
  }



  Future<void> _analyzeUserMessageForNotificationNormal(String userMessage) async {
    try {
      final url = Uri.parse('https://api.anthropic.com/v1/messages');
      const systemPrompt = """
Analyse le message suivant et détermine s'il contient une information future ou un sentiment.
Si c'est le cas, retourne un JSON avec le type d'information et le délai avant d'envoyer une notification.
Format de réponse JSON:
{
  "hasNotification": true/false,
  "type": "event/sentiment",
  "delayInMinutes": X
}
""";

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-3-haiku-20240307',
          'max_tokens': 100,
          'system': systemPrompt,
          'messages': [
            {'role': 'user', 'content': userMessage},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final analysisText = data['content'][0]['text'];
        final analysis = jsonDecode(analysisText);

        if (analysis['hasNotification']) {
          final delayInMinutes = analysis['delayInMinutes'];
          _scheduleNotification(userMessage, delayInMinutes);
        }
      }
    } catch (e) {
      print("Erreur lors de l'analyse du message pour la notification: $e");
    }
  }

  Future<List<Map<String, dynamic>>> _getLastMessages() async {
    try {
      final messagesSnapshot =
      await _firestore
          .collection('users')
          .doc(widget.userId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(5)
          .get();

      return messagesSnapshot.docs.map((doc) {
        return {
          'text': doc.data()['text'] ?? '',
          'isUser': doc.data()['isUser'] ?? false,
          'timestamp': doc.data()['timestamp'] ?? DateTime.now(),
        };
      }).toList();
    } catch (e) {
      print("Erreur lors de la récupération des derniers messages: $e");
      return [];
    }
  }

  Future<void> _analyzePersonalityRequest(String userMessage) async {
    try {
      final url = Uri.parse('https://api.anthropic.com/v1/messages');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-3-haiku-20240307',
          'max_tokens': 100,
          'system': """
          Analyse si ce message contient une demande de changement de personnalité pour l'IA.
          Exemples: "Je veux que tu sois plus formel", "Réponds comme un pirate", etc.
          Format de réponse JSON uniquement:
          {
            "isPersonalityRequest": true/false,
            "personality": "description de la personnalité demandée"
          }
          """,
          'messages': [
            {'role': 'user', 'content': userMessage},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final analysisText = data['content'][0]['text'];
        final analysis = jsonDecode(analysisText);

        if (analysis['isPersonalityRequest']) {
          await _savePersonality(analysis['personality']);
        }
      }
    } catch (e) {
      print("Erreur d'analyse de personnalité: $e");
    }
  }

  // Nouvelle méthode pour sauvegarder la personnalité
  Future<void> _savePersonality(String personality) async {
    try {
      // Sauvegarder la nouvelle personnalité
      await _firestore.collection('users').doc(widget.userId).update({
        'aiPersonality': personality,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      setState(() {
        _currentPersonality = personality;
      });
    } catch (e) {
      print("Erreur lors de la sauvegarde de la personnalité: $e");
      rethrow;
    }
  }

  // Mise à jour de la fonction _showPersonalityDialog
  Future<void> _showPersonalityDialog(BuildContext context) async {
    try {
      // Récupérer la personnalité actuelle
      final userDoc =
      await _firestore.collection('users').doc(widget.userId).get();
      final currentPersonality = userDoc.data()?['aiPersonality'] ?? "Standard";

      // Récupérer les traits de personnalité depuis 'aiPersonalityInfo'
      final List<String> personalityTraits = List<String>.from(
        userDoc.data()?['aiPersonalityInfo']?.split('\n') ?? [],
      );

      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Personnalité de l\'IA'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Personnalité actuelle:'),
                  const SizedBox(height: 8),
                  Text(
                    currentPersonality,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Traits de personnalité appris:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  // Afficher les traits de personnalité
                  ...personalityTraits.map(
                        (trait) => Padding(
                      padding: const EdgeInsets.only(left: 16, top: 4),
                      child: Text('• $trait'),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer'),
              ),
              TextButton(
                onPressed: () async {
                  await _savePersonality("Standard");
                  Navigator.of(context).pop();
                },
                child: const Text('Réinitialiser'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      print("Erreur lors de l'affichage de la personnalité: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Impossible de récupérer la personnalité de l'IA."),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _analyzeAndStoreUserInfo(String userMessage) async {
    try {
      final url = Uri.parse('https://api.anthropic.com/v1/messages');

      const systemPrompt = """
    Analyse le message suivant et extrait uniquement les informations pertinentes sur l'utilisateur.
    Concentre-toi sur les faits, préférences, détails personnels ou informations utiles.
    Format de réponse STRICT en JSON :
    {
      "informations": [
        "information extraite 1",
        "information extraite 2"
      ]
    }
    """;

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-3-haiku-20240307',
          'max_tokens': 100,
          'system': systemPrompt,
          'messages': [
            {'role': 'user', 'content': userMessage},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final analysisText = data['content'][0]['text'];

        // Nettoyer la réponse pour extraire uniquement le JSON
        final cleanedText =
        analysisText.replaceAll('```json', '').replaceAll('```', '').trim();

        try {
          final analysisData = jsonDecode(cleanedText);
          final List<dynamic> informations = analysisData['informations'] ?? [];

          // Ne continuer que si de nouvelles informations ont été extraites
          if (informations.isNotEmpty) {
            // Récupérer le texte existant
            final userDoc =
            await _firestore.collection('users').doc(widget.userId).get();
            String existingText = userDoc.data()?['userInfo'] ?? '';

            // Si des nouvelles informations sont trouvées, créer un prompt pour reformuler
            final newInfos =
            informations
                .where(
                  (info) =>
              info is String &&
                  info.isNotEmpty &&
                  !existingText.contains(info),
            )
                .toList();

            if (newInfos.isNotEmpty) {
              // Utiliser Claude pour reformuler le texte
              final reformulatedText = await _reformulateUserInfo(
                existingText,
                newInfos,
              );

              // Mettre à jour le texte dans Firestore
              await _firestore.collection('users').doc(widget.userId).update({
                'userInfo': reformulatedText,
                'lastUpdated': FieldValue.serverTimestamp(),
              });
            }
          }
        } catch (e) {
          print("Erreur de parsing JSON dans _analyzeAndStoreUserInfo: $e");
          print("Texte reçu: $cleanedText");
        }
      }
    } catch (e) {
      print("Erreur dans _analyzeAndStoreUserInfo: $e");
    }
  }

  // Nouvelle fonction pour reformuler les informations utilisateur
  Future<String> _reformulateUserInfo(
      String existingInfo,
      List<dynamic> newInfos,
      ) async {
    try {
      final url = Uri.parse('https://api.anthropic.com/v1/messages');

      String newInfosText = newInfos.join("\n");
      String promptContent = """
    Voici les informations existantes sur un utilisateur:
    
    $existingInfo
    
    Voici de nouvelles informations à intégrer:
    
    $newInfosText
    
    Crée un texte cohérent qui combine ces informations de manière naturelle, sans répétitions.
    Si les nouvelles informations contredisent les anciennes, garde les plus récentes.
    Présente les informations de façon claire et organisée par thèmes si possible.
    """;

      // Si c'est la première information, simplifie le prompt
      if (existingInfo.isEmpty) {
        promptContent = """
      Voici des informations sur un utilisateur:
      
      $newInfosText
      
      Rédige un texte cohérent qui présente ces informations de façon claire et organisée.
      """;
      }

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-3-haiku-20240307',
          'max_tokens': 500,
          'system':
          "Tu es un assistant qui reformule des informations en un texte cohérent et bien organisé.",
          'messages': [
            {'role': 'user', 'content': promptContent},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['content'][0]['text'];
      } else {
        print("Erreur API lors de la reformulation: ${response.statusCode}");
        // En cas d'erreur, concaténer simplement
        return existingInfo.isEmpty
            ? newInfosText
            : "$existingInfo\n$newInfosText";
      }
    } catch (e) {
      print("Erreur lors de la reformulation: $e");
      // En cas d'erreur, concaténer simplement
      return existingInfo.isEmpty
          ? newInfos.join("\n")
          : "$existingInfo\n${newInfos.join("\n")}";
    }
  }

  Future<void> _loadEmotionalHealth() async {
    try {
      final userDoc =
      await _firestore.collection('users').doc(widget.userId).get();
      if (userDoc.exists && userDoc.data()!.containsKey('emotionalHealth')) {
        setState(() {
          _emotionalHealth = userDoc.data()!['emotionalHealth'];
          _negativeMessageCount = userDoc.data()!['negativeMessageCount'] ?? 0;
          _positiveMessageCount = userDoc.data()!['positiveMessageCount'] ?? 0;
        });
      } else {
        // Initialiser les valeurs par défaut dans Firestore
        await _saveEmotionalState();
      }
    } catch (e) {
      print("Erreur lors du chargement de l'état émotionnel: $e");
    }
  }

  // Sauvegarder l'état émotionnel dans Firestore
  Future<void> _saveEmotionalState() async {
    try {
      await _firestore.collection('users').doc(widget.userId).update({
        'emotionalHealth': _emotionalHealth,
        'negativeMessageCount': _negativeMessageCount,
        'positiveMessageCount': _positiveMessageCount,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Erreur lors de la sauvegarde de l'état émotionnel: $e");
    }
  }

  // Initialiser le chat
  Future<void> _initializeChat() async {
    try {
      // Charger la personnalité actuelle
      final userDoc =
      await _firestore.collection('users').doc(widget.userId).get();
      if (userDoc.exists && userDoc.data()!.containsKey('aiPersonality')) {
        setState(() {
          _currentPersonality = userDoc.data()!['aiPersonality'];
        });
        print("Personnalité chargée: $_currentPersonality"); // Ajoutez ce log
      }
      // Mettre à jour la dernière activité de l'utilisateur
      await _firestore.collection('users').doc(widget.userId).update({
        'lastActive': FieldValue.serverTimestamp(),
      });

      // Charger les messages précédents
      await _loadPreviousMessages();

      setState(() {
        _isInitialized = true;
        if (_messages.isEmpty) {
          // Ajouter un message de bienvenue si aucun message n'existe
          _messages.add(
            const ChatMessage(
              text: "Bonjour ! Comment puis-je vous aider aujourd'hui ?",
              isUserMessage: false,
            ),
          );
        }
      });
    } catch (e) {
      print("Erreur d'initialisation du chat: $e");
      setState(() {
        _isInitialized = true;
        _messages.add(
          const ChatMessage(
            text: "Une erreur s'est produite lors de l'initialisation du chat.",
            isUserMessage: false,
            isError: true,
          ),
        );
      });
    }
  }

  // Charger les messages précédents depuis Firestore
  Future<void> _loadPreviousMessages() async {
    try {
      final messagesSnapshot =
      await _firestore
          .collection('users')
          .doc(widget.userId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();

      final List<ChatMessage> loadedMessages = [];
      for (var doc in messagesSnapshot.docs) {
        loadedMessages.add(
          ChatMessage(
            text: doc.data()['text'] ?? '',
            isUserMessage: doc.data()['isUser'] ?? false,
            isError: doc.data()['isError'] ?? false,
          ),
        );
      }

      setState(() {
        _messages.addAll(loadedMessages.reversed);
      });
    } catch (e) {
      print("Erreur lors du chargement des messages: $e");
    }
  }

  // Envoyer un message à l'API Claude
  Future<void> _handleSubmitted(String text) async {
    if (text.trim().isEmpty) return;

    _textController.clear();

    ChatMessage userMessage = ChatMessage(text: text, isUserMessage: true);

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });

    try {
      // 1. Sauvegarder d'abord le message de l'utilisateur
      await _saveMessageToFirestore(text, true);

      await handleMessageSent(text);

      await _analyzePersonalityRequest(text);

      // 2. Mettre à jour la dernière activité de l'utilisateur
      await _firestore.collection('users').doc(widget.userId).update({
        'lastActive': FieldValue.serverTimestamp(),
      });

      // 3. Lancer en parallèle l'analyse du sentiment et l'analyse des informations
      final Future<double> sentimentFuture = _analyzeSentiment(text);
      final Future<void> infoAnalysisFuture = _analyzeAndStoreUserInfo(text);

      // Attendre les deux analyses
      final sentimentScore = await sentimentFuture;
      await infoAnalysisFuture; // S'assurer que l'analyse des informations est terminée

      // 4. Mettre à jour l'état émotionnel après l'analyse du sentiment
      await _updateEmotionalHealth(sentimentScore);

      // 5. Obtenir le contexte utilisateur mis à jour
      final userInfo = await _getUserInformation();

      // 6. Générer la réponse de Claude avec le contexte
      String response = await _sendMessageToClaude(text, userInfo);



      // 8. Ajouter et sauvegarder la réponse
      ChatMessage aiMessage = ChatMessage(text: response, isUserMessage: false);

      setState(() {
        _messages.add(aiMessage);
        _isLoading = false;
      });

      await _saveMessageToFirestore(response, false);
    } catch (e) {
      print("Erreur dans _handleSubmitted: $e");
      setState(() {
        _messages.add(
          const ChatMessage(
            text: "Désolé, une erreur s'est produite. Veuillez réessayer.",
            isUserMessage: false,
            isError: true,
          ),
        );
        _isLoading = false;
      });
    }
  }

  Future<void> handleMessageSent(String userMessage) async {
    // Augmenter le score de toutes les notifications
    await updatePoint();

    // Vérifier si le message correspond à des mots-clés existants
    bool foundMatch = false;

    // Récupérer les notifications existantes
    final userDoc = await _firestore.collection('users').doc(widget.userId).get();
    final userData = userDoc.data();

    if (userData != null && userData.containsKey('scheduledNotifications')) {
      List<dynamic> notifications = List.from(userData['scheduledNotifications']);

      // Comparer avec les mots-clés de chaque notification
      for (int i = 0; i < notifications.length; i++) {
        List<String> keywords = List<String>.from(notifications[i]['keywords'] ?? []);

        // Vérifier si un mot-clé correspond au message
        if (keywords.any((keyword) => userMessage.toLowerCase().contains(keyword.toLowerCase()))) {
          await _updateFirestore(userMessage, notifications[i], i);
          foundMatch = true;
          break;
        }
      }
    }

    // Si aucune correspondance n'est trouvée, analyser pour une nouvelle notification
    if (!foundMatch) {
      await analyzeUserMessageForNotification(userMessage);
    }
  }

  // Méthode pour mettre à jour les points de toutes les notifications d'un utilisateur
  Future<void> updatePoint() async {
    try {
      // Récupérer le document utilisateur
      final userDoc = await _firestore.collection('users').doc(widget.userId).get();
      final userData = userDoc.data();

      if (userData != null && userData.containsKey('scheduledNotifications')) {
        List<dynamic> notifications = List.from(userData['scheduledNotifications']);
        bool updated = false;

        // Mettre à jour chaque notification
        for (int i = 0; i < notifications.length; i++) {
          if (notifications[i]['score'] < 3) { // Ne pas dépasser 3 points
            notifications[i] = {
              ...notifications[i],
              'score': notifications[i]['score'] + 1
            };
            updated = true;
          }
        }

        // Sauvegarder les modifications dans Firestore si au moins une notification a été mise à jour
        if (updated) {
          await _firestore.collection('users').doc(widget.userId).update({
            'scheduledNotifications': notifications,
          });

          // Re-planifier les notifications avec OneSignal si nécessaire
          for (var notification in notifications) {
            if (notification['score'] > 0) {
              await _rescheduleNotificationWithOneSignal(notification);
            }
          }
        }
      }
    } catch (e) {
      print("Erreur lors de la mise à jour des points de notification: $e");
    }
  }

// Méthode pour mettre à jour une notification existante correspondant aux mots-clés
  Future<void> _updateFirestore(String userMessage, Map<String, dynamic> matchingNotification, int index) async {
    try {
      // Récupérer le document utilisateur
      final userDoc = await _firestore.collection('users').doc(widget.userId).get();
      final userData = userDoc.data();

      if (userData != null && userData.containsKey('scheduledNotifications')) {
        List<dynamic> notifications = List.from(userData['scheduledNotifications']);

        // Générer un nouveau contenu pour la notification mise à jour
        final url = Uri.parse('https://api.anthropic.com/v1/messages');
        final systemPrompt = """
Voici une notification existante et un nouveau message de l'utilisateur. 
Mets à jour la notification et les mots-clés pour refléter les nouvelles informations.

Notification existante: "${matchingNotification['message']}"
Mots-clés existants: ${matchingNotification['keywords']}

Format JSON uniquement:
{
  "updatedMessage": "Notification mise à jour et améliorée",
  "updatedKeywords": ["mot1", "mot2", "mot3"]
}
""";

        final response = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': _apiKey,
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode({
            'model': 'claude-3-haiku-20240307',
            'max_tokens': 150,
            'system': systemPrompt,
            'messages': [
              {'role': 'user', 'content': userMessage},
            ],
          }),
        );

        Map<String, dynamic> updatedContent;

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final analysisText = data['content'][0]['text'];

          // Extraire uniquement le JSON
          final cleanedText = analysisText
              .replaceAll('```json', '')
              .replaceAll('```', '')
              .trim();

          final analysis = jsonDecode(cleanedText);

          updatedContent = {
            'message': analysis['updatedMessage'],
            'keywords': analysis['updatedKeywords'],
          };
        } else {
          // Fallback si l'API échoue
          final List<String> existingKeywords = List<String>.from(matchingNotification['keywords'] ?? []);
          final List<String> newKeywords = _extractKeywords(userMessage);
          final Set<String> allKeywords = {...existingKeywords, ...newKeywords};

          updatedContent = {
            'message': "Mise à jour: " + (userMessage.length > 30 ? userMessage.substring(0, 30) + '...' : userMessage),
            'keywords': allKeywords.toList().take(5).toList(),
          };
        }

        // Mettre à jour la notification
        notifications[index] = {
          ...notifications[index],
          'message': updatedContent['message'],
          'keywords': updatedContent['keywords'],
          'score': matchingNotification['score'] < 3
              ? matchingNotification['score'] + 1
              : matchingNotification['score'],
        };

        // Sauvegarder les modifications dans Firestore
        await _firestore.collection('users').doc(widget.userId).update({
          'scheduledNotifications': notifications,
        });

        // Re-planifier la notification avec OneSignal
        await _rescheduleNotificationWithOneSignal(notifications[index]);

        print("Notification mise à jour avec succès: ${updatedContent['message']}");
      }
    } catch (e) {
      print("Erreur lors de la mise à jour de la notification: $e");

      // Fallback simple en cas d'erreur
      try {
        final userDoc = await _firestore.collection('users').doc(widget.userId).get();
        final userData = userDoc.data();

        if (userData != null && userData.containsKey('scheduledNotifications')) {
          List<dynamic> notifications = List.from(userData['scheduledNotifications']);

          // Augmenter uniquement le score sans modifier le contenu
          notifications[index] = {
            ...notifications[index],
            'score': matchingNotification['score'] < 3
                ? matchingNotification['score'] + 1
                : matchingNotification['score'],
          };

          await _firestore.collection('users').doc(widget.userId).update({
            'scheduledNotifications': notifications,
          });
        }
      } catch (fallbackError) {
        print("Erreur lors de la mise à jour de secours: $fallbackError");
      }
    }
  }

// Méthode pour analyser si un message doit générer une notification en cas de contenu négatif
  Future<void> analyzeUserMessageForNotification(String userMessage) async {
    try {
      final url = Uri.parse('https://api.anthropic.com/v1/messages');
      const systemPrompt = """
Analyse le message suivant et détermine s'il contient des signes de correction, de changement d'avis, ou de rétraction.
Évalue des expressions telles que "non finalement", "je me suis trompé", "désolé", ou d'autres tournures indiquant un ajustement ou un retour en arrière.
Retourne un JSON indiquant si le message implique un changement d'avis ou une correction.
Format de réponse JSON :
{
  "isCorrection": true/false
}
""";

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-3-haiku-20240307',
          'max_tokens': 150,
          'system': systemPrompt,
          'messages': [
            {'role': 'user', 'content': userMessage},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final analysisText = data['content'][0]['text'];
        final analysis = jsonDecode(analysisText);

        if (analysis['isCorrection'] == true) {
          // Vérifier s'il existe une notification avec moins de 2 points
          final userDoc = await _firestore.collection('users').doc(widget.userId).get();
          final userData = userDoc.data();

          if (userData != null && userData.containsKey('scheduledNotifications')) {
            List<dynamic> notifications = List.from(userData['scheduledNotifications']);
            int notificationIndex = -1;

            // Chercher une notification avec moins de 2 points
            for (int i = 0; i < notifications.length; i++) {
              if (notifications[i]['score'] < 2) {
                notificationIndex = i;
                break;
              }
            }

            if (notificationIndex >= 0) {
              // Mettre à jour la notification existante
              await _updateFirestore(userMessage, notifications[notificationIndex], notificationIndex);
            } else {
              // Aucune notification avec moins de 2 points trouvée
              // Envoyer un message demandant quelle notification modifier
              ChatMessage aiMessage = const ChatMessage(
                  text: "Voulez-vous modifier une notification ? De quelle notification parlez-vous ?",
                  isUserMessage: false
              );

              setState(() {
                _messages.add(aiMessage);
              });

              await _saveMessageToFirestore(
                  "Voulez-vous modifier une notification ? De quelle notification parlez-vous ?",
                  false
              );
            }
          } else {
            // Aucune notification existante, créer une nouvelle
            await _analyzeUserMessageForNotificationNormal(userMessage);
          }
        } else {
          // Si le message n'est pas négatif, analyser pour une notification normale
          await _analyzeUserMessageForNotificationNormal(userMessage);
        }
      } else {
        print("Erreur lors de l'analyse du message: ${response.statusCode} - ${response.body}");
        // En cas d'erreur, essayer d'analyser pour une notification normale
        await _analyzeUserMessageForNotificationNormal(userMessage);
      }
    } catch (e) {
      print("Erreur lors de l'analyse du message pour la notification: $e");
      // En cas d'erreur, essayer d'analyser pour une notification normale
      await _analyzeUserMessageForNotificationNormal(userMessage);
    }
  }

  Future<double> _analyzeSentiment(String text) async {
    try {
      final url = Uri.parse('https://api.anthropic.com/v1/messages');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-3-haiku-20240307',
          'max_tokens': 100,
          'system': """
          Analyse le sentiment émotionnel du message envers l'IA.
          Retourne uniquement un score entre -1.0 (très négatif/hostile) et 1.0 (très positif/amical).
          Format de réponse attendu: {"score": X.X}
          """,
          'messages': [
            {'role': 'user', 'content': text},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final analysisText = data['content'][0]['text'];
        final analysis = jsonDecode(analysisText);
        return analysis['score'].toDouble();
      }
      return 0.0;
    } catch (e) {
      print("Erreur d'analyse du sentiment: $e");
      return 0.0;
    }
  }

  Future<void> _updateEmotionalHealth(double sentimentScore) async {
    setState(() {
      if (sentimentScore < 0) {
        _negativeMessageCount++;
        double impact = math.pow(_negativeMessageCount, 1.5).toDouble() * 2;
        _emotionalHealth = math.max(0, _emotionalHealth - impact);
      } else if (sentimentScore > 0) {
        _positiveMessageCount++;
        double impact = math.min(
          5.0,
          sentimentScore * 3 / math.sqrt(_negativeMessageCount + 1),
        );
        _emotionalHealth = math.min(100, _emotionalHealth + impact);
      }
    });

    try {
      await _firestore.collection('users').doc(widget.userId).update({
        'emotionalHealth': _emotionalHealth,
        'negativeMessageCount': _negativeMessageCount,
        'positiveMessageCount': _positiveMessageCount,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Erreur lors de la sauvegarde de l'état émotionnel: $e");
    }
  }


  // Sauvegarder un message dans Firestore
  Future<void> _saveMessageToFirestore(
      String text,
      bool isUser, {
        bool isError = false,
      }) async {
    try {
      await _firestore
          .collection('users')
          .doc(widget.userId)
          .collection('messages')
          .add({
        'text': text,
        'isUser': isUser,
        'isError': isError,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Erreur lors de la sauvegarde du message: $e");
    }
  }

  Future<Map<String, dynamic>> _getUserInformation() async {
    final Map<String, dynamic> userInfo = {
      'info': '', // Initialize with an empty string
    };

    try {
      final userDoc =
      await _firestore.collection('users').doc(widget.userId).get();
      userInfo['info'] =
          userDoc.data()?['userInfo'] ?? ''; // Get the userInfo string
    } catch (e) {
      print("Erreur lors de la récupération des informations: $e");
    }

    return userInfo; // Return the map
  }

  // Envoyer le message à l'API Claude avec contexte
  Future<String> _sendMessageToClaude(
      String userMessage,
      Map<String, dynamic> userContext,
      ) async {
    try {
      final url = Uri.parse('https://api.anthropic.com/v1/messages');

      // Récupérer les 5 derniers messages de l'utilisateur
      final lastMessages = await _getLastMessages();

      // Récupérer les informations sur la personnalité de l'IA
      final userDoc = await _firestore.collection('users').doc(widget.userId).get();
      final String aiPersonalityInfo = userDoc.data()?['aiPersonalityInfo'] ?? '';

      // Construire un système prompt avec les informations contextuelles
      String systemPrompt = """
    Fais des réponses très courtes, en une seule phrase, comme un SMS. Concentre-toi sur l'essentiel.
""";

      // Ajouter la personnalité demandée si elle existe
      if (_currentPersonality.isNotEmpty && _currentPersonality != "Standard") {
        systemPrompt += "\nPersonnalité demandée: $_currentPersonality\nAdapte ton style de réponse pour correspondre à cette personnalité.";
      }

      // Ajouter les informations sur la personnalité de l'IA si elles existent
      if (aiPersonalityInfo.isNotEmpty) {
        systemPrompt += "\n\nInformations sur ta personnalité (traits et préférences que tu as exprimés précédemment):\n" + aiPersonalityInfo;
        systemPrompt += "\nUtilise ces informations pour maintenir une personnalité cohérente dans tes réponses.";
      }

      // Ajouter les informations sur l'utilisateur si elles existent
      if (userContext.isNotEmpty && userContext['info'] != null && userContext['info'].isNotEmpty) {
        systemPrompt += "\n\nVoici des informations importantes que l'utilisateur a partagées:\n" + userContext['info'];
        systemPrompt += "\nUtilise ces informations pour personnaliser ta réponse et montrer que tu te souviens des détails partagés par l'utilisateur.";
      }

      // Ajouter les 5 derniers messages au contexte
      if (lastMessages.isNotEmpty) {
        systemPrompt += "\n\nVoici les 5 derniers messages de la conversation pour contexte:";
        for (var message in lastMessages) {
          systemPrompt += "\n- ${message['isUser'] ? 'Utilisateur' : 'IA'}: ${message['text']}";
        }
      }

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-3-sonnet-20240229',
          'max_tokens': 5, // Augmenté pour permettre des réponses plus détaillées
          'system': systemPrompt,
          'messages': [
            {'role': 'user', 'content': userMessage},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final aiResponse = data['content'][0]['text'];

        // Analyser la réponse de l'IA pour extraire des informations sur sa personnalité
        await _analyzeAndStoreAIPersonality(aiResponse);

        return aiResponse;
      } else {
        print("Erreur API Claude: ${response.statusCode} - ${response.body}");
        return "Je suis désolé, je n'ai pas pu traiter votre demande. Erreur ${response.statusCode}";
      }
    } catch (e) {
      print("Exception lors de l'appel API: $e");
      return "Je suis désolé, une erreur s'est produite. Veuillez réessayer plus tard.";
    }
  }

  // Nouvelle fonction pour analyser la réponse de l'IA
  Future<void> _analyzeAndStoreAIPersonality(String aiMessage) async {
    try {
      final url = Uri.parse('https://api.anthropic.com/v1/messages');

      const systemPrompt = """
    Analyse le message suivant et extrait uniquement les informations pertinentes sur l'IA.
    Concentre-toi sur les faits, préférences, détails personnels ou informations utiles.
    Format de réponse STRICT en JSON :
    {
      "information": [
        "information extraite 1",
        "information extraite 2"
      ]
    }
    """;

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-3-haiku-20240307',
          'max_tokens': 100,
          'system': systemPrompt,
          'messages': [
            {'role': 'user', 'content': aiMessage},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final analysisText = data['content'][0]['text'];

        // Nettoyer la réponse pour extraire uniquement le JSON
        final cleanedText =
        analysisText.replaceAll('```json', '').replaceAll('```', '').trim();

        try {
          final analysisData = jsonDecode(cleanedText);
          final List<dynamic> personality = analysisData['information'] ?? [];

          // Ne continuer que si de nouvelles informations ont été extraites
          if (personality.isNotEmpty) {
            // Récupérer les informations existantes sur la personnalité de l'IA
            final userDoc =
            await _firestore.collection('users').doc(widget.userId).get();
            String existingPersonality =
                userDoc.data()?['aiPersonalityInfo'] ?? '';

            // Si des nouvelles informations sont trouvées, créer un prompt pour reformuler
            final newTraits =
            personality
                .where(
                  (trait) =>
              trait is String &&
                  trait.isNotEmpty &&
                  !existingPersonality.contains(trait),
            )
                .toList();

            if (newTraits.isNotEmpty) {
              // Utiliser Claude pour reformuler le texte
              final reformulatedText = await _reformulateAIPersonality(
                existingPersonality,
                newTraits,
              );

              // Mettre à jour Firestore avec le texte reformulé
              await _firestore.collection('users').doc(widget.userId).update({
                'aiPersonalityInfo': reformulatedText,
                'lastUpdated': FieldValue.serverTimestamp(),
              });
            }
          }
        } catch (e) {
          print(
            "Erreur de parsing JSON dans _analyzeAndStoreAIPersonality: $e",
          );
        }
      }
    } catch (e) {
      print("Erreur dans _analyzeAndStoreAIPersonality: $e");
    }
  }

  Future<String> _reformulateAIPersonality(
      String existingPersonality,
      List<dynamic> newTraits,
      ) async {
    try {
      final url = Uri.parse('https://api.anthropic.com/v1/messages');

      String newTraitsText = newTraits.join("\n");
      String promptContent = """
    Voici les traits de personnalité existants d'une IA:
    
    $existingPersonality
    
    Voici de nouveaux traits à intégrer:
    
    $newTraitsText
    
    Rédige un texte cohérent qui combine ces traits de façon organisée par thèmes.
    Si les nouveaux traits contredisent les anciens, garde les plus récents.
    """;

      // Si c'est le premier trait, simplifie le prompt
      if (existingPersonality.isEmpty) {
        promptContent = """
      Voici des traits de personnalité d'une IA:
      
      $newTraitsText
      
      Rédige un texte cohérent qui présente ces traits de façon organisée.
      """;
      }

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-3-haiku-20240307',
          'max_tokens': 500,
          'system':
          "Tu es un assistant qui reformule des informations en un texte cohérent et bien organisé.",
          'messages': [
            {'role': 'user', 'content': promptContent},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['content'][0]['text'];
      } else {
        print("Erreur API lors de la reformulation: ${response.statusCode}");
        // En cas d'erreur, concaténer simplement
        return existingPersonality.isEmpty
            ? newTraitsText
            : "$existingPersonality\n$newTraitsText";
      }
    } catch (e) {
      print("Erreur lors de la reformulation: $e");
      // En cas d'erreur, concaténer simplement
      return existingPersonality.isEmpty
          ? newTraits.join("\n")
          : "$existingPersonality\n${newTraits.join("\n")}";
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Assistant IA')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant IA'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4.0),
          child: LinearProgressIndicator(
            value: _emotionalHealth / 100,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              _emotionalHealth > 70
                  ? Colors.green
                  : _emotionalHealth > 40
                  ? Colors.orange
                  : Colors.red,
            ),
          ),
        ),
        actions: [
          Center(
            child: Text(
              '${_emotionalHealth.toStringAsFixed(1)}%',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.psychology,
            ), // Nouveau bouton pour la personnalité
            onPressed: () => _showPersonalityDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showUserInfoDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () => _showScheduledNotificationsDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _showLogoutDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (_, index) {
                return _messages[_messages.length - 1 - index];
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(),
            ),
          const Divider(height: 1.0),
          Container(
            decoration: BoxDecoration(color: Theme.of(context).cardColor),
            child: _buildTextComposer(),
          ),
        ],
      ),
    );
  }

  // Construire le champ de saisie et le bouton d'envoi
  Widget _buildTextComposer() {
    return IconTheme(
      data: IconThemeData(color: Theme.of(context).primaryColor),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          children: [
            Flexible(
              child: TextField(
                controller: _textController,
                onSubmitted: _isLoading ? null : _handleSubmitted,
                decoration: const InputDecoration.collapsed(
                  hintText: 'Envoyer un message',
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed:
              _isLoading
                  ? null
                  : () => _handleSubmitted(_textController.text),
            ),
          ],
        ),
      ),
    );
  }

  // Afficher une boîte de dialogue avec les informations stockées de l'utilisateur
  Future<void> _showUserInfoDialog(BuildContext context) async {
    try {
      // Récupérer le texte des informations utilisateur
      final userDoc =
      await _firestore.collection('users').doc(widget.userId).get();
      final String userInfo = userDoc.data()?['userInfo'] ?? '';

      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Informations mémorisées'),
            content: SingleChildScrollView(
              child:
              userInfo.isEmpty
                  ? const Text('Aucune information mémorisée.')
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:
                userInfo
                    .split('\n') // Diviser le texte en lignes
                    .map(
                      (info) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text('• $info'),
                  ),
                )
                    .toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      print("Erreur lors de l'affichage des informations: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Impossible de récupérer les informations mémorisées."),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // Afficher une boîte de dialogue de déconnexion
  Future<void> _showLogoutDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Déconnexion'),
          content: const Text('Voulez-vous vraiment vous déconnecter ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await _auth.signOut();
                  Navigator.of(context).pop();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Erreur lors de la déconnexion: $e"),
                    ),
                  );
                }
              },
              child: const Text('Déconnecter'),
            ),
          ],
        );
      },
    );
  }
}
void _showNotificationPermissionDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Notifications désactivées'),
        content: const Text('Pour recevoir des notifications, veuillez les activer dans les paramètres de votre appareil.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => openAppSettings(),
            child: const Text('Ouvrir les paramètres'),
          ),
        ],
      );
    },
  );
}

@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('Notifications'),
    ),
    body: Center(
      child: ElevatedButton(
        onPressed: () async {
          await requestNotificationPermission(context); // Passer le contexte ici
        },
        child: const Text('Demander les permissions'),
      ),
    ),
  );
}
Future<void> requestNotificationPermission(BuildContext context) async {
  final status = await Permission.notification.request();
  if (status.isGranted) {
    print("Notifications autorisées");
  } else {
    print("Notifications non autorisées");
    _showNotificationPermissionDialog(context); // Passer le contexte ici
  }
}

class ChatMessage extends StatelessWidget {
  final String text;
  final bool isUserMessage;
  final bool isSystemMessage;
  final bool isError;

  const ChatMessage({
    Key? key,
    required this.text,
    required this.isUserMessage,
    this.isSystemMessage = false,
    this.isError = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              backgroundColor:
              isSystemMessage
                  ? Colors.grey
                  : isUserMessage
                  ? Colors.blue
                  : isError
                  ? Colors.red
                  : Colors.green,
              child: Icon(
                isSystemMessage
                    ? Icons.info
                    : isUserMessage
                    ? Icons.person
                    : isError
                    ? Icons.error
                    : Icons.smart_toy,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSystemMessage
                      ? 'Système'
                      : isUserMessage
                      ? 'Vous'
                      : isError
                      ? 'Erreur'
                      : 'Assistant',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 5.0),
                  child: Text(text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}