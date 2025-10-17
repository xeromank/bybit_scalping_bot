/// API-related constants
///
/// Responsibility: Centralize all API-related constants
///
/// This class contains all API endpoints, URLs, and API-related configuration.
class ApiConstants {
  ApiConstants._(); // Private constructor to prevent instantiation

  // Base URLs
  static const String baseUrlMainnet = 'https://api.bybit.com';
  static const String baseUrlTestnet = 'https://api-testnet.bybit.com';

  // Use testnet by default for safety
  static const String baseUrl = baseUrlTestnet;

  // API Version
  static const String apiVersion = 'v5';

  // Request timeout
  static const Duration requestTimeout = Duration(seconds: 30);

  // Receive window (milliseconds)
  static const int recvWindow = 5000;

  // API Endpoints
  static const String endpointServerTime = '/v5/market/time';
  static const String endpointWalletBalance = '/v5/account/wallet-balance';
  static const String endpointSetLeverage = '/v5/position/set-leverage';
  static const String endpointCreateOrder = '/v5/order/create';
  static const String endpointCancelOrder = '/v5/order/cancel';
  static const String endpointCancelAllOrders = '/v5/order/cancel-all';
  static const String endpointGetPositions = '/v5/position/list';
  static const String endpointGetTicker = '/v5/market/tickers';
  static const String endpointGetActiveOrders = '/v5/order/realtime';

  // Account Types
  static const String accountTypeUnified = 'UNIFIED';
  static const String accountTypeContract = 'CONTRACT';
  static const String accountTypeSpot = 'SPOT';

  // Category Types
  static const String categoryLinear = 'linear';
  static const String categoryInverse = 'inverse';
  static const String categorySpot = 'spot';
  static const String categoryOption = 'option';

  // Order Types
  static const String orderTypeMarket = 'Market';
  static const String orderTypeLimit = 'Limit';

  // Order Sides
  static const String orderSideBuy = 'Buy';
  static const String orderSideSell = 'Sell';

  // Time in Force
  static const String timeInForceGTC = 'GTC'; // Good Till Cancel
  static const String timeInForceIOC = 'IOC'; // Immediate or Cancel
  static const String timeInForceFOK = 'FOK'; // Fill or Kill
  static const String timeInForcePostOnly = 'PostOnly';

  // Position Index
  static const int positionIdxOneWay = 0;
  static const int positionIdxHedgeBuySide = 1;
  static const int positionIdxHedgeSellSide = 2;

  // Response Codes
  static const int responseCodeSuccess = 0;
  static const int responseCodeInvalidApiKey = 10003;
  static const int responseCodeInvalidSignature = 10004;
}
