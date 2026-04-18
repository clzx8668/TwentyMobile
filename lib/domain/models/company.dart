import 'package:freezed_annotation/freezed_annotation.dart';

part 'company.freezed.dart';
part 'company.g.dart';

@freezed
class Company with _$Company {
  factory Company({
    required String id,
    required String name,
    String? domainName,
    String? industry,
    String? website,
    String? logoUrl,
    String? linkedinUrl,
    String? xUrl,
    int? employeesCount,
    DateTime? createdAt,
  }) = _Company;

  factory Company.fromJson(Map<String, dynamic> json) =>
      _$CompanyFromJson(json);

  factory Company.fromTwenty(Map<String, dynamic> json) {
    String? _primaryLinkUrl(dynamic v) {
      if (v is Map) {
        final url = v['primaryLinkUrl'];
        if (url is String && url.isNotEmpty) return url;
      }
      if (v is String && v.isNotEmpty) return v;
      return null;
    }

    // domainName è un oggetto Links in Twenty CRM
    String? domainName;
    final dn = json['domainName'];
    if (dn is Map) {
      domainName = dn['primaryLinkUrl'] as String?;
    } else if (dn is String && dn.isNotEmpty) {
      domainName = dn;
    }
    // Rimuovi protocollo (https://) per display
    if (domainName != null && domainName.contains('://')) {
      domainName = Uri.tryParse(domainName)?.host ?? domainName;
    }

    return Company(
      id: json['id'],
      name: json['name'] is Map ? json['name']['text'] ?? '' : json['name'] ?? '',
      domainName: domainName?.isNotEmpty == true ? domainName : null,
      logoUrl: json['logoUrl'] as String?,
      employeesCount: json['employees'] as int?,
      industry: json['industry'] as String?,
      website: _primaryLinkUrl(json['website']),
      linkedinUrl: _primaryLinkUrl(json['linkedinLink']),
      xUrl: _primaryLinkUrl(json['xLink']),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
    );
  }
}
