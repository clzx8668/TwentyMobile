import 'package:freezed_annotation/freezed_annotation.dart';

part 'contact.freezed.dart';
part 'contact.g.dart';

@freezed
class Contact with _$Contact {
  factory Contact({
    required String id,
    required String firstName,
    required String lastName,
    String? email,
    String? phone,
    String? avatarUrl,
    String? companyId,
    String? companyName,
    String? jobTitle,
    String? city,
    String? linkedinUrl,
    String? xUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _Contact;

  factory Contact.fromJson(Map<String, dynamic> json) =>
      _$ContactFromJson(json);

  factory Contact.fromTwenty(Map<String, dynamic> json) {
    String? primaryLinkUrl(dynamic v) {
      if (v is Map) {
        final url = v['primaryLinkUrl'];
        if (url is String && url.isNotEmpty) return url;
      }
      if (v is String && v.isNotEmpty) return v;
      return null;
    }

    final companyData = json['company'];
    String? companyName;
    if (companyData != null) {
      final nameVal = companyData['name'];
      companyName = nameVal is Map ? nameVal['text'] : nameVal;
    }

    final rawAvatar = json['avatarUrl'];
    final avatarUrl = (rawAvatar is String && rawAvatar.startsWith('http'))
        ? rawAvatar
        : null;
    final phones = json['phones'];
    String? parsedPhone;
    if (phones != null) {
      final callingCode = phones['primaryPhoneCallingCode'] ?? '';
      final number = phones['primaryPhoneNumber'] ?? '';
      if (callingCode.isNotEmpty || number.isNotEmpty) {
        parsedPhone = '$callingCode$number';
      }
    }

    return Contact(
      id: json['id'],
      firstName: json['name']?['firstName'] ?? '',
      lastName: json['name']?['lastName'] ?? '',
      email: json['emails']?['primaryEmail'],
      phone: parsedPhone,
      avatarUrl: avatarUrl,
      companyName: companyName,
      companyId: companyData?['id'],
      jobTitle: json['jobTitle'] as String?,
      city: json['city'] as String?,
      linkedinUrl: primaryLinkUrl(json['linkedinLink']),
      xUrl: primaryLinkUrl(json['xLink']),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }
}
