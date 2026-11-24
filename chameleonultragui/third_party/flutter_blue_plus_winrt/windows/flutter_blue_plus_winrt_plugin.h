#ifndef FLUTTER_PLUGIN_FLUTTER_BLUE_PLUS_WINRT_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_BLUE_PLUS_WINRT_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Foundation.h>

#include <memory>
#include <string>
#include <vector>
#include <utility>
#include <map>
#include <atomic>
#include <mutex>

namespace flutter_blue_plus_winrt {

struct SubscribedCharacteristic {
    winrt::Windows::Foundation::IInspectable characteristic = nullptr;
    winrt::event_token token;
};

class FlutterBluePlusWinrtPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FlutterBluePlusWinrtPlugin(flutter::PluginRegistrarWindows* registrar);

  ~FlutterBluePlusWinrtPlugin();

  // Disallow copy and assign.
  FlutterBluePlusWinrtPlugin(const FlutterBluePlusWinrtPlugin&) = delete;
  FlutterBluePlusWinrtPlugin& operator=(const FlutterBluePlusWinrtPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementWatcher watcher_{};
  winrt::event_token received_token_{};
  winrt::event_token stopped_token_{};
  
  // Shared "alive" flag. Held by a shared_ptr so that fire-and-forget
  // coroutines / event handlers can capture a copy and safely check whether
  // the plugin has been destroyed after resuming, instead of dereferencing a
  // dangling `this`.
  std::shared_ptr<std::atomic<bool>> is_alive_ = std::make_shared<std::atomic<bool>>(true);

  // UI Thread context
  winrt::apartment_context ui_thread_;

  std::mutex devices_mutex_;
  std::vector<std::pair<std::string, winrt::Windows::Foundation::IInspectable>> connected_devices_{};
  std::vector<std::pair<std::string, winrt::Windows::Foundation::IInspectable>> currently_connecting_devices_{};
  std::map<std::string, int32_t> rssi_cache_{};
  
  std::map<std::string, std::map<flutter::EncodableValue, flutter::EncodableValue>> scan_results_cache_{};

  // Map to store event tokens and characteristic objects for notifications
  std::map<std::string, SubscribedCharacteristic> subscribed_characteristics_{};

  // Guards the GATT object caches below (characteristic_cache_,
  // descriptor_cache_, service_cache_, subscribed_characteristics_,
  // gatt_sessions_, mtu_tokens_, connection_params_requests_,
  // connection_tokens_). These are accessed both
  // from background thread-pool continuations (service discovery / read /
  // write) and from the UI thread (ClearDeviceResources on disconnect), so
  // every access must hold this mutex. NOTE: never hold this across a
  // `co_await`.
  std::mutex gatt_cache_mutex_;

  // Caches for GATT objects to avoid repeated discovery
  std::map<std::string, winrt::Windows::Foundation::IInspectable> characteristic_cache_{};
  std::map<std::string, winrt::Windows::Foundation::IInspectable> descriptor_cache_{};
  std::map<std::string, std::vector<winrt::Windows::Foundation::IInspectable>> service_cache_{};

  // MTU / Session Handling
  std::map<std::string, winrt::Windows::Foundation::IInspectable> gatt_sessions_{};
  std::map<std::string, winrt::event_token> mtu_tokens_{};
  // Windows 11 BluetoothLEPreferredConnectionParametersRequest per device.
  // The short connection interval holds only while the request is open.
  std::map<std::string, winrt::Windows::Foundation::IInspectable> connection_params_requests_{};
  // Revokes, closes and forgets the session, MTU token and connection
  // parameters request of one device. Caller holds gatt_cache_mutex_.
  void CloseSessionLocked(const std::string& remote_id);

  // Per-device ConnectionStatusChanged event tokens, so the handlers can be
  // revoked (in ClearDeviceResources and the destructor) and never fire into a
  // destroyed plugin. Guarded by gatt_cache_mutex_.
  std::map<std::string, winrt::event_token> connection_tokens_{};

  void OnAdvertisementReceived(
      const winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementWatcher&,
      const winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementReceivedEventArgs&);

  void OnAdvertisementStopped(
      const winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementWatcher&,
      const winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementWatcherStoppedEventArgs&);
  
  winrt::fire_and_forget GetSystemDevicesAsync(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  winrt::fire_and_forget GetAdapterStateAsync(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  winrt::fire_and_forget StartScanAsync(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  winrt::fire_and_forget GetBondedDevicesAsync(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  winrt::fire_and_forget CreateBondAsync(
      std::string remote_id,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  winrt::fire_and_forget RemoveBondAsync(
      std::string remote_id,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  winrt::fire_and_forget GetBondStateAsync(
      std::string remote_id,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  winrt::fire_and_forget ConnectAsync(
      std::string remote_id,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  winrt::fire_and_forget DiscoverServicesAsync(
      std::string remote_id,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  
  winrt::fire_and_forget SetNotifyValueAsync(
      std::shared_ptr<flutter::EncodableMap> args);

  winrt::fire_and_forget ReadCharacteristicAsync(
      flutter::EncodableMap args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  winrt::fire_and_forget WriteCharacteristicAsync(
      flutter::EncodableMap args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  winrt::fire_and_forget ReadDescriptorAsync(
      flutter::EncodableMap args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  winrt::fire_and_forget WriteDescriptorAsync(
      flutter::EncodableMap args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void OnConnectionStatusChanged(
    const winrt::Windows::Devices::Bluetooth::BluetoothLEDevice&,
    const winrt::Windows::Foundation::IInspectable&);

  void OnCharacteristicValueChanged(
      std::string remote_id,
      const winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattCharacteristic& sender,
      const winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattValueChangedEventArgs& args);

  void OnMaxPduSizeChanged(
      std::string remote_id,
      const winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattSession& sender,
      const winrt::Windows::Foundation::IInspectable& args);

  winrt::fire_and_forget PeriodicConnectionCheck();

  std::string uint64_to_mac_string(uint64_t addr);

  // --- Private GATT Helpers ---
  winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattCharacteristic> 
  GetCharacteristicInternalAsync(
      winrt::Windows::Devices::Bluetooth::BluetoothLEDevice device,
      std::string remote_id,
      std::string service_uuid_str,
      std::string characteristic_uuid_str,
      std::string primary_service_uuid_str,
      int instance_id);

  winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattCharacteristic> 
  GetCharacteristicByHandleAsync(
      winrt::Windows::Devices::Bluetooth::BluetoothLEDevice device,
      int instance_id);

  winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattCharacteristic> 
  GetCharacteristicAsync(
      winrt::Windows::Devices::Bluetooth::BluetoothLEDevice device,
      std::string service_uuid_str,
      std::string characteristic_uuid_str,
      std::string primary_service_uuid_str,
      int instance_id);

  winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattCharacteristic> 
  FindCharacteristicInServiceAsync(
      winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattDeviceService service,
      int instance_id,
      winrt::Windows::Devices::Bluetooth::BluetoothCacheMode cacheMode);

  winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattCharacteristic> 
  FindCharacteristicByDescriptorHandleInServiceAsync(
      winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattDeviceService service,
      int descriptor_handle,
      winrt::Windows::Devices::Bluetooth::BluetoothCacheMode cacheMode);

  winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattCharacteristic> 
  GetCharacteristicByDescriptorHandleAsync(
      winrt::Windows::Devices::Bluetooth::BluetoothLEDevice device,
      int descriptor_handle);

  winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattDescriptor> 
  GetDescriptorAsync(
      winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattCharacteristic characteristic,
      std::string descriptor_uuid_str);

  winrt::Windows::Foundation::IAsyncAction PopulateCharacteristicsAsync(
      winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattDeviceService service,
      std::string remote_id,
      std::string primaryServiceUuid,
      std::shared_ptr<flutter::EncodableList> outList);

  void ClearDeviceResources(std::string remote_id);
};

}  // namespace flutter_blue_plus_winrt

#endif  // FLUTTER_PLUGIN_FLUTTER_BLUE_PLUS_WINRT_PLUGIN_H_
