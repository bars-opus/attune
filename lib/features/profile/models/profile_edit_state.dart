class ProfileEditState {
  final String displayName;
  final String username;
  final String bio;
  final bool isSavingDisplayName;
  final bool isSavingUsername;
  final bool isSavingBio;
  final String? displayNameError;
  final String? usernameError;
  final String? bioError;

  ProfileEditState({
    required this.displayName,
    required this.username,
    required this.bio,
    this.isSavingDisplayName = false,
    this.isSavingUsername = false,
    this.isSavingBio = false,
    this.displayNameError,
    this.usernameError,
    this.bioError,
  });

  ProfileEditState copyWith({
    String? displayName,
    String? username,
    String? bio,
    bool? isSavingDisplayName,
    bool? isSavingUsername,
    bool? isSavingBio,
    String? displayNameError,
    String? usernameError,
    String? bioError,
  }) {
    return ProfileEditState(
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      bio: bio ?? this.bio,
      isSavingDisplayName: isSavingDisplayName ?? this.isSavingDisplayName,
      isSavingUsername: isSavingUsername ?? this.isSavingUsername,
      isSavingBio: isSavingBio ?? this.isSavingBio,
      displayNameError: displayNameError ?? this.displayNameError,
      usernameError: usernameError ?? this.usernameError,
      bioError: bioError ?? this.bioError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'displayName': displayName,
      'username': username,
      'bio': bio,
      'isSavingDisplayName': isSavingDisplayName,
      'isSavingUsername': isSavingUsername,
      'isSavingBio': isSavingBio,
      'displayNameError': displayNameError,
      'usernameError': usernameError,
      'bioError': bioError,
    };
  }

  factory ProfileEditState.fromJson(Map<String, dynamic> json) {
    return ProfileEditState(
      displayName: json['displayName'],
      username: json['username'],
      bio: json['bio'],
      isSavingDisplayName: json['isSavingDisplayName'] ?? false,
      isSavingUsername: json['isSavingUsername'] ?? false,
      isSavingBio: json['isSavingBio'] ?? false,
      displayNameError: json['displayNameError'],
      usernameError: json['usernameError'],
      bioError: json['bioError'],
    );
  }
}
