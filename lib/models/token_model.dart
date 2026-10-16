import 'dart:convert';

TokenModel tokenModelFromJson(String str) => TokenModel.fromJson(json.decode(str));

String tokenModelToJson(TokenModel data) => json.encode(data.toJson());

class TokenModel {
    final String accessToken;
    final String refreshToken;

    TokenModel({
        required this.accessToken,
        required this.refreshToken,
    });

    factory TokenModel.fromJson(Map<String, dynamic> json) => TokenModel(
        accessToken: json["accessToken"],
        refreshToken: json["refreshToken"],
    );

    Map<String, dynamic> toJson() => {
        "accessToken": accessToken,
        "refreshToken": refreshToken,
    };
}