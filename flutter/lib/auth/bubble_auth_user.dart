import '../models/user_struct.dart';

/// Client-side auth state model.
class BubbleAuthUser {
  final bool loggedIn;
  final String? uid;
  final UserStruct? userData;

  BubbleAuthUser({
    required this.loggedIn,
    this.uid,
    this.userData,
  });
}
