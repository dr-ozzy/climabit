/// Município usado nas consultas às fontes oficiais.
class Cidade {
  const Cidade({
    required this.nome,
    required this.uf,
    required this.geocode,
    this.idCptec,
    this.latitude,
    this.longitude,
    this.idEccc,
  });

  /// Código da cidade no serviço meteorológico do Canadá (ECCC), ex.: "on-143" (Toronto).
  /// Nulo nas cidades do Brasil.
  final String? idEccc;

  bool get noCanada => idEccc != null;

  final String nome;
  final String uf;

  /// Código IBGE do município (usado por INMET e Cemaden).
  final int geocode;

  /// Código da cidade no CPTEC/INPE.
  final int? idCptec;

  final double? latitude;
  final double? longitude;

  bool get ehRioDeJaneiro => geocode == 3304557;
  bool get ehNiteroi => geocode == 3303302;
  bool get ehItajuba => geocode == 3132404;

  /// A mesma cidade com outro ponto (sede do município).
  Cidade comPosicao(double lat, double lon) => Cidade(
        nome: nome,
        uf: uf,
        geocode: geocode,
        idCptec: idCptec,
        latitude: lat,
        longitude: lon,
        idEccc: idEccc,
      );

  Cidade comIdCptec(int id) => Cidade(
        nome: nome,
        uf: uf,
        geocode: geocode,
        idCptec: id,
        latitude: latitude,
        longitude: longitude,
        idEccc: idEccc,
      );

  String get rotulo => noCanada ? '$nome – Canadá' : '$nome – $uf';

  Map<String, Object?> toJson() => {
        'nome': nome,
        'uf': uf,
        'geocode': geocode,
        'idCptec': idCptec,
        'latitude': latitude,
        'longitude': longitude,
        if (idEccc != null) 'idEccc': idEccc,
      };

  factory Cidade.fromJson(Map<String, Object?> j) => Cidade(
        nome: j['nome'] as String,
        uf: j['uf'] as String,
        geocode: j['geocode'] as int,
        idCptec: j['idCptec'] as int?,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        idEccc: j['idEccc'] as String?,
      );

  @override
  bool operator ==(Object other) => other is Cidade && other.geocode == geocode;

  @override
  int get hashCode => geocode.hashCode;
}

const niteroi = Cidade(
  nome: 'Niterói',
  uf: 'RJ',
  geocode: 3303302,
  idCptec: 3464,
  // Sede municipal (IBGE, Localidades 2022).
  latitude: -22.8929,
  longitude: -43.1183,
);
