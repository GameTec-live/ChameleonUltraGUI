#pragma warning(disable : 4819)

#include "flutter_blue_plus_winrt_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <Windows.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>

#include <memory>
#include <sstream>
#include <iomanip>
#include <algorithm>
#include <vector>
#include <exception>
#include <cstdarg>
#include <chrono>

using namespace winrt;
using namespace Windows::Foundation;
using namespace Windows::Foundation::Collections;
using namespace Windows::Devices::Bluetooth;
using namespace Windows::Devices::Bluetooth::Advertisement;
using namespace Windows::Devices::Bluetooth::GenericAttributeProfile;
using namespace Windows::Devices::Enumeration;
using namespace Windows::Devices::Radios;

namespace flutter_blue_plus_winrt {

// Debug Logging Helper
void Log(const char* format, ...) {
    char buffer[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    std::string msg = "[FBP-Win] ";
    msg += buffer;
    msg += "\n";
    OutputDebugStringA(msg.c_str());
}

namespace utils {
std::string to_string(const winrt::hstring& hstr) {
    return winrt::to_string(hstr);
}

template <typename T>
T from_value(const flutter::EncodableValue* value) {
    if (auto* ptr = std::get_if<T>(value)) {
        return *ptr;
    }
    if constexpr (std::is_integral_v<T> && !std::is_same_v<T, bool>) {
        if (auto* ptr64 = std::get_if<int64_t>(value)) {
            return static_cast<T>(*ptr64);
        }
        if (auto* ptr32 = std::get_if<int32_t>(value)) {
            return static_cast<T>(*ptr32);
        }
    }
    return T{};
}

uint64_t mac_to_uint64(const std::string& mac_address) {
    std::stringstream ss(mac_address);
    uint64_t result = 0;
    for (int i = 0; i < 6; ++i) {
        long long byte;
        ss >> std::hex >> byte;
        result = (result << 8) | byte;
        if (i < 5) {
            ss.ignore();
        }
    }
    return result;
}

std::vector<uint8_t> to_vector(const winrt::Windows::Storage::Streams::IBuffer& buffer) {
    auto reader = winrt::Windows::Storage::Streams::DataReader::FromBuffer(buffer);
    std::vector<uint8_t> data(reader.UnconsumedBufferLength());
    if (!data.empty()) {
        reader.ReadBytes(data);
    }
    return data;
}

std::string to_uuid_string(const winrt::guid& uuid) {
    std::string uuid_str_with_braces = winrt::to_string(winrt::to_hstring(uuid));
    std::string full_uuid;

    if (uuid_str_with_braces.length() >= 2 && uuid_str_with_braces.front() == '{' && uuid_str_with_braces.back() == '}') {
        full_uuid = uuid_str_with_braces.substr(1, uuid_str_with_braces.length() - 2);
    } else {
        full_uuid = uuid_str_with_braces;
    }

    std::transform(full_uuid.begin(), full_uuid.end(), full_uuid.begin(),
                   [](unsigned char c){ return static_cast<char>(std::tolower(c)); });

    if (full_uuid.length() == 36 &&
        full_uuid.substr(0, 4) == "0000" &&
        full_uuid.substr(8) == "-0000-1000-8000-00805f9b34fb") {
        return full_uuid.substr(4, 4);
    }
    return full_uuid;
}

winrt::guid parse_uuid(const std::string& uuid_str) {
    std::string full_uuid = uuid_str;
    if (full_uuid.length() == 4) {
        full_uuid = "0000" + full_uuid + "-0000-1000-8000-00805f9b34fb";
    }
    else if (full_uuid.length() == 8) {
        full_uuid = full_uuid + "-0000-1000-8000-00805f9b34fb";
    }
    
    if (full_uuid.length() > 0 && full_uuid.front() != '{') {
        full_uuid = "{" + full_uuid + "}";
    }

    std::wstring wstr(full_uuid.begin(), full_uuid.end());
    GUID guid;
    if (SUCCEEDED(IIDFromString(wstr.c_str(), &guid))) {
        return winrt::guid(guid);
    }
    return winrt::guid();
}

}  // namespace utils

// --- GATT Helper Members ---

winrt::Windows::Foundation::IAsyncOperation<GattCharacteristic> 
FlutterBluePlusWinrtPlugin::FindCharacteristicInServiceAsync(
    GattDeviceService service,
    int instance_id,
    BluetoothCacheMode cacheMode)
{
    try {
        auto charsResult = co_await service.GetCharacteristicsAsync(cacheMode);
        if (charsResult.Status() == GattCommunicationStatus::Success) {
            for (auto c : charsResult.Characteristics()) {
                if (instance_id != 0 && static_cast<int32_t>(c.AttributeHandle()) == instance_id) {
                    co_return c;
                }
            }
        }

        auto includedResult = co_await service.GetIncludedServicesAsync(cacheMode);
        if (includedResult.Status() == GattCommunicationStatus::Success) {
            for (auto includedService : includedResult.Services()) {
                auto c = co_await FindCharacteristicInServiceAsync(includedService, instance_id, cacheMode);
                if (c) co_return c;
            }
        }
    } catch (...) {}
    co_return nullptr;
}

winrt::Windows::Foundation::IAsyncOperation<GattCharacteristic> 
FlutterBluePlusWinrtPlugin::FindCharacteristicByDescriptorHandleInServiceAsync(
    GattDeviceService service,
    int descriptor_handle,
    BluetoothCacheMode cacheMode)
{
    if (descriptor_handle == 0) co_return nullptr;

    try {
        auto charsResult = co_await service.GetCharacteristicsAsync(cacheMode);
        if (charsResult.Status() == GattCommunicationStatus::Success) {
            for (auto c : charsResult.Characteristics()) {
                 auto descResult = co_await c.GetDescriptorsAsync(cacheMode);
                 if (descResult.Status() == GattCommunicationStatus::Success) {
                     for (auto d : descResult.Descriptors()) {
                         if (static_cast<int32_t>(d.AttributeHandle()) == descriptor_handle) {
                             co_return c;
                         }
                     }
                 }
            }
        }

        auto includedResult = co_await service.GetIncludedServicesAsync(cacheMode);
        if (includedResult.Status() == GattCommunicationStatus::Success) {
            for (auto includedService : includedResult.Services()) {
                auto c = co_await FindCharacteristicByDescriptorHandleInServiceAsync(includedService, descriptor_handle, cacheMode);
                if (c) co_return c;
            }
        }
    } catch (...) {}
    co_return nullptr;
}

winrt::Windows::Foundation::IAsyncOperation<GattCharacteristic> 
FlutterBluePlusWinrtPlugin::GetCharacteristicByHandleAsync(
    BluetoothLEDevice device,
    int instance_id)
{
    auto servicesResult = co_await device.GetGattServicesAsync(BluetoothCacheMode::Cached);
    if (servicesResult.Status() == GattCommunicationStatus::Success) {
        for (auto service : servicesResult.Services()) {
            auto c = co_await FindCharacteristicInServiceAsync(service, instance_id, BluetoothCacheMode::Cached);
            if (c) co_return c;
        }
    }

    servicesResult = co_await device.GetGattServicesAsync(BluetoothCacheMode::Uncached);
    if (servicesResult.Status() == GattCommunicationStatus::Success) {
        for (auto service : servicesResult.Services()) {
            auto c = co_await FindCharacteristicInServiceAsync(service, instance_id, BluetoothCacheMode::Uncached);
            if (c) co_return c;
        }
    }
    co_return nullptr;
}

winrt::Windows::Foundation::IAsyncOperation<GattCharacteristic> 
FlutterBluePlusWinrtPlugin::GetCharacteristicByDescriptorHandleAsync(
    BluetoothLEDevice device,
    int descriptor_handle)
{
    auto servicesResult = co_await device.GetGattServicesAsync(BluetoothCacheMode::Cached);
    if (servicesResult.Status() == GattCommunicationStatus::Success) {
        for (auto service : servicesResult.Services()) {
            auto c = co_await FindCharacteristicByDescriptorHandleInServiceAsync(service, descriptor_handle, BluetoothCacheMode::Cached);
            if (c) co_return c;
        }
    }
    servicesResult = co_await device.GetGattServicesAsync(BluetoothCacheMode::Uncached);
    if (servicesResult.Status() == GattCommunicationStatus::Success) {
        for (auto service : servicesResult.Services()) {
            auto c = co_await FindCharacteristicByDescriptorHandleInServiceAsync(service, descriptor_handle, BluetoothCacheMode::Uncached);
            if (c) co_return c;
        }
    }
    co_return nullptr;
}

winrt::Windows::Foundation::IAsyncOperation<GattCharacteristic> 
FlutterBluePlusWinrtPlugin::GetCharacteristicAsync(
    BluetoothLEDevice device,
    std::string service_uuid_str,
    std::string characteristic_uuid_str,
    std::string primary_service_uuid_str,
    int instance_id)
{
    GattCharacteristic targetChar = nullptr;
    winrt::guid targetServiceUuid = utils::parse_uuid(service_uuid_str);
    winrt::guid targetCharUuid = utils::parse_uuid(characteristic_uuid_str);

    if (!primary_service_uuid_str.empty()) {
        winrt::guid primaryUuid = utils::parse_uuid(primary_service_uuid_str);
        GattDeviceServicesResult primaryResult = co_await device.GetGattServicesForUuidAsync(primaryUuid, BluetoothCacheMode::Cached);
        if (primaryResult.Status() != GattCommunicationStatus::Success || primaryResult.Services().Size() == 0) {
             primaryResult = co_await device.GetGattServicesForUuidAsync(primaryUuid, BluetoothCacheMode::Uncached);
        }

        if (primaryResult.Status() == GattCommunicationStatus::Success) {
            for (auto primaryService : primaryResult.Services()) {
                GattDeviceServicesResult includedResult = co_await primaryService.GetIncludedServicesForUuidAsync(targetServiceUuid, BluetoothCacheMode::Cached);
                if (includedResult.Status() != GattCommunicationStatus::Success || includedResult.Services().Size() == 0) {
                     includedResult = co_await primaryService.GetIncludedServicesForUuidAsync(targetServiceUuid, BluetoothCacheMode::Uncached);
                }

                if (includedResult.Status() == GattCommunicationStatus::Success) {
                    for (auto service : includedResult.Services()) {
                        GattCharacteristicsResult charsResult = co_await service.GetCharacteristicsForUuidAsync(targetCharUuid, BluetoothCacheMode::Cached);
                        if (charsResult.Status() != GattCommunicationStatus::Success || charsResult.Characteristics().Size() == 0) {
                             charsResult = co_await service.GetCharacteristicsForUuidAsync(targetCharUuid, BluetoothCacheMode::Uncached);
                        }

                        if (charsResult.Status() == GattCommunicationStatus::Success) {
                            for (auto characteristic : charsResult.Characteristics()) {
                                if (instance_id == 0 || static_cast<int32_t>(characteristic.AttributeHandle()) == instance_id) {
                                    targetChar = characteristic;
                                    break;
                                }
                            }
                        }
                        if (targetChar) break;
                    }
                }
                if (targetChar) break;
            }
        }
    } else {
        GattDeviceServicesResult servicesResult = co_await device.GetGattServicesForUuidAsync(targetServiceUuid, BluetoothCacheMode::Cached);
        if (servicesResult.Status() != GattCommunicationStatus::Success || servicesResult.Services().Size() == 0) {
             servicesResult = co_await device.GetGattServicesForUuidAsync(targetServiceUuid, BluetoothCacheMode::Uncached);
        }

        if (servicesResult.Status() == GattCommunicationStatus::Success) {
            for (auto service : servicesResult.Services()) {
                if (service.Uuid() == targetServiceUuid) {
                     GattCharacteristicsResult charsResult = co_await service.GetCharacteristicsForUuidAsync(targetCharUuid, BluetoothCacheMode::Cached);
                     if (charsResult.Status() != GattCommunicationStatus::Success || charsResult.Characteristics().Size() == 0) {
                          charsResult = co_await service.GetCharacteristicsForUuidAsync(targetCharUuid, BluetoothCacheMode::Uncached);
                     }
                     if (charsResult.Status() == GattCommunicationStatus::Success && charsResult.Characteristics().Size() > 0) {
                          for (auto c : charsResult.Characteristics()) {
                                if(instance_id == 0 || static_cast<int32_t>(c.AttributeHandle()) == instance_id) {
                                    targetChar = c;
                                    break;
                                }
                          }
                     }
                }
                if (targetChar) break;
            }
        }
    }
    co_return targetChar;
}

winrt::Windows::Foundation::IAsyncOperation<GattDescriptor> 
FlutterBluePlusWinrtPlugin::GetDescriptorAsync(
    GattCharacteristic characteristic,
    std::string descriptor_uuid_str)
{
    if (!characteristic) co_return nullptr;

    winrt::guid descUuid = utils::parse_uuid(descriptor_uuid_str);
    GattDescriptor targetDesc = nullptr;

    auto descResult = co_await characteristic.GetDescriptorsForUuidAsync(descUuid, BluetoothCacheMode::Cached);
    if (descResult.Status() == GattCommunicationStatus::Success) {
        for (auto descriptor : descResult.Descriptors()) {
            if (utils::to_uuid_string(descriptor.Uuid()) == descriptor_uuid_str) {
                targetDesc = descriptor; break;
            }
        }
    }

    if (!targetDesc) {
        descResult = co_await characteristic.GetDescriptorsForUuidAsync(descUuid, BluetoothCacheMode::Uncached);
        if (descResult.Status() == GattCommunicationStatus::Success) {
            for (auto descriptor : descResult.Descriptors()) {
                if (utils::to_uuid_string(descriptor.Uuid()) == descriptor_uuid_str) {
                    targetDesc = descriptor; break;
                }
            }
        }
    }
    co_return targetDesc;
}

winrt::Windows::Foundation::IAsyncAction 
FlutterBluePlusWinrtPlugin::PopulateCharacteristicsAsync(
    GattDeviceService service,
    std::string remote_id,
    std::string primaryServiceUuid,
    std::shared_ptr<flutter::EncodableList> outList)
{
    auto charsResult = co_await service.GetCharacteristicsAsync(BluetoothCacheMode::Cached);
    if (charsResult.Status() != GattCommunicationStatus::Success || charsResult.Characteristics().Size() == 0) {
        charsResult = co_await service.GetCharacteristicsAsync(BluetoothCacheMode::Uncached);
    }

    if (charsResult.Status() == GattCommunicationStatus::Success) {
        for (auto characteristic : charsResult.Characteristics()) {
            try {
                flutter::EncodableMap charMap;
                std::string serviceUuid = utils::to_uuid_string(service.Uuid());
                std::string charUuid = utils::to_uuid_string(characteristic.Uuid());
                int32_t handle = static_cast<int32_t>(characteristic.AttributeHandle());

                {
                    std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_);
                    characteristic_cache_[remote_id + ":" + std::to_string(handle)] = characteristic;
                }

                charMap[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
                if (!primaryServiceUuid.empty()) {
                    charMap[flutter::EncodableValue("primary_service_uuid")] = flutter::EncodableValue(primaryServiceUuid);
                }
                charMap[flutter::EncodableValue("service_uuid")] = flutter::EncodableValue(serviceUuid);
                charMap[flutter::EncodableValue("characteristic_uuid")] = flutter::EncodableValue(charUuid);
                charMap[flutter::EncodableValue("instance_id")] = flutter::EncodableValue(handle);

                auto props = characteristic.CharacteristicProperties();
                flutter::EncodableMap propsMap;
                propsMap[flutter::EncodableValue("broadcast")] = flutter::EncodableValue((static_cast<uint32_t>(props) & static_cast<uint32_t>(GattCharacteristicProperties::Broadcast)) ? 1 : 0);
                propsMap[flutter::EncodableValue("read")] = flutter::EncodableValue((static_cast<uint32_t>(props) & static_cast<uint32_t>(GattCharacteristicProperties::Read)) ? 1 : 0);
                propsMap[flutter::EncodableValue("write_without_response")] = flutter::EncodableValue((static_cast<uint32_t>(props) & static_cast<uint32_t>(GattCharacteristicProperties::WriteWithoutResponse)) ? 1 : 0);
                propsMap[flutter::EncodableValue("write")] = flutter::EncodableValue((static_cast<uint32_t>(props) & static_cast<uint32_t>(GattCharacteristicProperties::Write)) ? 1 : 0);
                propsMap[flutter::EncodableValue("notify")] = flutter::EncodableValue((static_cast<uint32_t>(props) & static_cast<uint32_t>(GattCharacteristicProperties::Notify)) ? 1 : 0);
                propsMap[flutter::EncodableValue("indicate")] = flutter::EncodableValue((static_cast<uint32_t>(props) & static_cast<uint32_t>(GattCharacteristicProperties::Indicate)) ? 1 : 0);
                propsMap[flutter::EncodableValue("authenticated_signed_writes")] = flutter::EncodableValue((static_cast<uint32_t>(props) & static_cast<uint32_t>(GattCharacteristicProperties::AuthenticatedSignedWrites)) ? 1 : 0);
                propsMap[flutter::EncodableValue("extended_properties")] = flutter::EncodableValue((static_cast<uint32_t>(props) & static_cast<uint32_t>(GattCharacteristicProperties::ExtendedProperties)) ? 1 : 0);
                propsMap[flutter::EncodableValue("notify_encryption_required")] = flutter::EncodableValue(0);
                propsMap[flutter::EncodableValue("indicate_encryption_required")] = flutter::EncodableValue(0);

                charMap[flutter::EncodableValue("properties")] = propsMap;

                auto descResult = co_await characteristic.GetDescriptorsAsync(BluetoothCacheMode::Cached);
                if (descResult.Status() != GattCommunicationStatus::Success) {
                     descResult = co_await characteristic.GetDescriptorsAsync(BluetoothCacheMode::Uncached);
                }

                flutter::EncodableList descList;
                if (descResult.Status() == GattCommunicationStatus::Success) {
                    for (auto descriptor : descResult.Descriptors()) {
                        try {
                            flutter::EncodableMap descMap;
                            int32_t d_handle = static_cast<int32_t>(descriptor.AttributeHandle());

                            {
                                std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_);
                                descriptor_cache_[remote_id + ":" + std::to_string(d_handle)] = descriptor;
                            }

                            descMap[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
                            if (!primaryServiceUuid.empty()) {
                                descMap[flutter::EncodableValue("primary_service_uuid")] = flutter::EncodableValue(primaryServiceUuid);
                            }
                            descMap[flutter::EncodableValue("service_uuid")] = flutter::EncodableValue(serviceUuid);
                            descMap[flutter::EncodableValue("characteristic_uuid")] = flutter::EncodableValue(charUuid);
                            descMap[flutter::EncodableValue("descriptor_uuid")] = flutter::EncodableValue(utils::to_uuid_string(descriptor.Uuid()));
                            descMap[flutter::EncodableValue("instance_id")] = flutter::EncodableValue(handle);
                            
                            descList.push_back(descMap);
                        } catch(...) {}
                    }
                }
                charMap[flutter::EncodableValue("descriptors")] = descList;
                outList->push_back(charMap);
            } catch(...) {}
        }
    }
    co_return;
}

winrt::Windows::Foundation::IAsyncOperation<GattCharacteristic> 
FlutterBluePlusWinrtPlugin::GetCharacteristicInternalAsync(
    BluetoothLEDevice device,
    std::string remote_id,
    std::string service_uuid_str,
    std::string characteristic_uuid_str,
    std::string primary_service_uuid_str,
    int instance_id)
{
    if (instance_id != 0) {
        std::string cache_key = remote_id + ":" + std::to_string(instance_id);
        winrt::Windows::Foundation::IInspectable cached = nullptr;
        {
            std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_);
            auto it = characteristic_cache_.find(cache_key);
            if (it != characteristic_cache_.end()) cached = it->second;
        }
        if (cached) co_return cached.as<GattCharacteristic>();
    }

    GattCharacteristic targetChar = nullptr;
    if (instance_id != 0) {
        targetChar = co_await GetCharacteristicByHandleAsync(device, instance_id);
    }
    if (!targetChar) {
        targetChar = co_await GetCharacteristicAsync(device, service_uuid_str, characteristic_uuid_str, primary_service_uuid_str, instance_id);
    }

    if (targetChar && instance_id != 0) {
        std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_);
        characteristic_cache_[remote_id + ":" + std::to_string(instance_id)] = targetChar;
    }
    co_return targetChar;
}

// --- Plugin Implementation ---

void FlutterBluePlusWinrtPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
    auto plugin = std::make_unique<FlutterBluePlusWinrtPlugin>(registrar);
    auto* plugin_pointer = plugin.get();

    plugin_pointer->channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(), "flutter_blue_plus/methods",
        &flutter::StandardMethodCodec::GetInstance());

    plugin_pointer->channel_->SetMethodCallHandler(
        [plugin_pointer](const auto& call, auto result) {
            plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
}

FlutterBluePlusWinrtPlugin::FlutterBluePlusWinrtPlugin(flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
    watcher_.ScanningMode(BluetoothLEScanningMode::Active);
    received_token_ = watcher_.Received(
        { this, &FlutterBluePlusWinrtPlugin::OnAdvertisementReceived });
    stopped_token_ = watcher_.Stopped(
        { this, &FlutterBluePlusWinrtPlugin::OnAdvertisementStopped });
    
    PeriodicConnectionCheck();
}

FlutterBluePlusWinrtPlugin::~FlutterBluePlusWinrtPlugin() {
    // Signal all in-flight coroutines / event handlers that the plugin is gone.
    // They capture a copy of this shared flag and bail out before touching
    // `this`, avoiding use-after-free during teardown.
    *is_alive_ = false;
    try { watcher_.Stop(); } catch (...) {}
    watcher_.Stopped(stopped_token_);
    watcher_.Received(received_token_);

    // Revoke any still-registered per-device ConnectionStatusChanged handlers
    // so a late event can't invoke OnConnectionStatusChanged on a destroyed
    // plugin. Lock order is devices_mutex_ then gatt_cache_mutex_ (never the
    // reverse anywhere), so this cannot deadlock.
    std::lock_guard<std::mutex> devices_lock(devices_mutex_);
    std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_);
    auto revoke_all = [this](const std::vector<std::pair<std::string, IInspectable>>& devices) {
        for (const auto& pair : devices) {
            auto it = connection_tokens_.find(pair.first);
            if (it == connection_tokens_.end()) continue;
            try { pair.second.as<BluetoothLEDevice>().ConnectionStatusChanged(it->second); } catch (...) {}
        }
    };
    revoke_all(connected_devices_);
    revoke_all(currently_connecting_devices_);
    connection_tokens_.clear();

    // Same for MaxPduSizeChanged, which also calls into `this`.
    std::vector<std::string> session_ids;
    for (const auto& pair : gatt_sessions_) session_ids.push_back(pair.first);
    for (const auto& id : session_ids) CloseSessionLocked(id);
}

void FlutterBluePlusWinrtPlugin::OnAdvertisementReceived(
    const BluetoothLEAdvertisementWatcher&,
    const BluetoothLEAdvertisementReceivedEventArgs& args) {

    [this, args, alive = is_alive_]() -> winrt::fire_and_forget {
        try {
            co_await ui_thread_;
            if (!*alive) co_return;

            if (channel_) {
                std::string remote_id = uint64_to_mac_string(args.BluetoothAddress());

                // Bound memory usage: a hostile environment can rotate BLE
                // addresses rapidly (address randomization / spoofing). Cap the
                // number of distinct devices tracked during a scan session so
                // the caches cannot grow without limit. Already-known devices
                // keep updating normally.
                constexpr size_t kMaxScanDevices = 4096;
                bool is_new_device = scan_results_cache_.find(remote_id) == scan_results_cache_.end();
                if (is_new_device && scan_results_cache_.size() >= kMaxScanDevices) {
                    co_return;
                }

                rssi_cache_[remote_id] = static_cast<int32_t>(args.RawSignalStrengthInDBm());

                if (is_new_device) {
                     scan_results_cache_[remote_id] = {};
                }
                auto& map = scan_results_cache_[remote_id];

                map[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
                map[flutter::EncodableValue("rssi")] = flutter::EncodableValue(static_cast<int32_t>(args.RawSignalStrengthInDBm()));

                int connectable = args.IsConnectable() ? 1 : 0;
                if (connectable == 0) {
                     auto it = map.find(flutter::EncodableValue("connectable"));
                     if (it != map.end()) {
                         if (auto* val = std::get_if<int>(&it->second)) {
                             if (*val == 1) connectable = 1;
                         }
                     }
                }
                map[flutter::EncodableValue("connectable")] = flutter::EncodableValue(connectable);

                auto advertisement = args.Advertisement();
                std::string localNameStr = utils::to_string(advertisement.LocalName());
                if (!localNameStr.empty()) {
                    map[flutter::EncodableValue("adv_name")] = flutter::EncodableValue(localNameStr);
                    map[flutter::EncodableValue("platform_name")] = flutter::EncodableValue(localNameStr);
                }

                if (args.TransmitPowerLevelInDBm() != nullptr) {
                    map[flutter::EncodableValue("tx_power_level")] =
                        flutter::EncodableValue(static_cast<int32_t>(args.TransmitPowerLevelInDBm().Value()));
                }

                for (const auto& section : advertisement.DataSections()) {
                    if (section.DataType() == 0x19) {
                        // Guard against a malformed/hostile peripheral sending an
                        // appearance section shorter than 2 bytes; ReadUInt16 would
                        // otherwise throw and abort processing of the whole packet.
                        if (section.Data().Length() < 2) break;
                        auto reader = winrt::Windows::Storage::Streams::DataReader::FromBuffer(section.Data());
                        reader.ByteOrder(winrt::Windows::Storage::Streams::ByteOrder::LittleEndian);
                        uint16_t appearance_value = reader.ReadUInt16();
                        map[flutter::EncodableValue("appearance")] = flutter::EncodableValue(static_cast<int32_t>(appearance_value));
                        break;
                    }
                }

                if (advertisement.ManufacturerData().Size() > 0) {
                    flutter::EncodableMap msd_map = flutter::EncodableMap();
                    for (const auto& msd : advertisement.ManufacturerData()) {
                        msd_map[flutter::EncodableValue(static_cast<int64_t>(msd.CompanyId()))] =
                            flutter::EncodableValue(utils::to_vector(msd.Data()));
                    }
                    map[flutter::EncodableValue("manufacturer_data")] = msd_map;
                }

                flutter::EncodableMap service_data_map;
                auto it_sd = map.find(flutter::EncodableValue("service_data"));
                if (it_sd != map.end()) {
                    if (auto* existing = std::get_if<flutter::EncodableMap>(&it_sd->second)) {
                        service_data_map = *existing;
                    }
                }

                bool has_new_service_data = false;
                for (const auto& section : advertisement.GetSectionsByType(0x16)) {
                     auto buffer = section.Data();
                     if (buffer.Length() >= 2) {
                         has_new_service_data = true;
                         auto all_data = utils::to_vector(buffer);
                         uint16_t uuid16 = (all_data[1] << 8) | all_data[0];
                         std::stringstream ss;
                         ss << std::hex << std::setfill('0') << std::setw(4) << uuid16;
                         std::string uuid_str = "0000" + ss.str() + "-0000-1000-8000-00805f9b34fb";
                         std::vector<uint8_t> data_vec(all_data.begin() + 2, all_data.end());
                         service_data_map[flutter::EncodableValue(uuid_str)] = flutter::EncodableValue(data_vec);
                     }
                }
                if (has_new_service_data || !service_data_map.empty()) {
                    map[flutter::EncodableValue("service_data")] = service_data_map;
                }

                if (advertisement.ServiceUuids().Size() > 0) {
                    flutter::EncodableList service_uuids_list;
                    auto it_u = map.find(flutter::EncodableValue("service_uuids"));
                    if (it_u != map.end()) {
                        if (auto* existing = std::get_if<flutter::EncodableList>(&it_u->second)) {
                            service_uuids_list = *existing;
                        }
                    }
                    for (const auto& uuid : advertisement.ServiceUuids()) {
                         std::string uuid_str = utils::to_uuid_string(uuid);
                         bool found = false;
                         for(const auto& existing_val : service_uuids_list) {
                             if (auto* s = std::get_if<std::string>(&existing_val)) {
                                 if (*s == uuid_str) { found = true; break; }
                             }
                         }
                         if (!found) service_uuids_list.push_back(flutter::EncodableValue(uuid_str));
                    }
                    map[flutter::EncodableValue("service_uuids")] = service_uuids_list;
                }

                flutter::EncodableMap response;
                response[flutter::EncodableValue("advertisements")] = flutter::EncodableList{ flutter::EncodableValue(map) };
                channel_->InvokeMethod("OnScanResponse", std::make_unique<flutter::EncodableValue>(response));
            }
        } catch (...) {}
    }();
}

void FlutterBluePlusWinrtPlugin::OnAdvertisementStopped(
    const BluetoothLEAdvertisementWatcher&,
    const BluetoothLEAdvertisementWatcherStoppedEventArgs&) {
}

winrt::fire_and_forget FlutterBluePlusWinrtPlugin::GetSystemDevicesAsync(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    std::string error_msg;
    try {
        // Broad selector for all Bluetooth LE devices using Association Endpoint protocol
        auto selector = L"System.Devices.Aep.ProtocolId:=\"{bb7bb05e-5972-42b5-9513-ade58156ee23}\"";
        
        Log("GetSystemDevices: Searching for connected BLE AEPs...");
        // Explicitly search for AssociationEndpoints
        auto deviceInfoCollection = co_await DeviceInformation::FindAllAsync(selector, {}, DeviceInformationKind::AssociationEndpoint);
        
        Log("GetSystemDevices: Found %d biological AEPs", deviceInfoCollection.Size());
        
        flutter::EncodableMap response = {};
        flutter::EncodableList deviceList;

        for (auto&& deviceInfo : deviceInfoCollection) {
            try {
                // Skip devices without a name as they are usually not useful
                if (deviceInfo.Name().empty()) continue;

                auto bleDevice = co_await BluetoothLEDevice::FromIdAsync(deviceInfo.Id());
                if (!bleDevice) continue;

                // User requested ONLY connected devices
                if (bleDevice.ConnectionStatus() == BluetoothConnectionStatus::Connected) {
                    std::string remote_id = uint64_to_mac_string(bleDevice.BluetoothAddress());
                    
                    flutter::EncodableMap deviceMap = {};
                    deviceMap[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
                    deviceMap[flutter::EncodableValue("platform_name")] = flutter::EncodableValue(utils::to_string(deviceInfo.Name()));
                    deviceMap[flutter::EncodableValue("connection_state")] = flutter::EncodableValue(1);
                    deviceList.push_back(flutter::EncodableValue(deviceMap));
                    
                    Log("  Added connected device: %ls (%s)", deviceInfo.Name().c_str(), remote_id.c_str());
                }
            } catch (...) {
                // Ignore failures for individual devices
            }
        }
        
        // Also ensure any devices connected directly by this app instance are included 
        // if they weren't already found by the system query (sometimes system cache lags)
        {
            std::lock_guard<std::mutex> lock(devices_mutex_);
            for (size_t i = 0; i < connected_devices_.size(); ++i) {
                const auto& pair = connected_devices_[i];
                bool already_added = false;
                for (const auto& val : deviceList) {
                    if (auto* m = std::get_if<flutter::EncodableMap>(&val)) {
                        auto it = m->find(flutter::EncodableValue("remote_id"));
                        if (it != m->end()) {
                            if (auto* s = std::get_if<std::string>(&it->second)) {
                                if (*s == pair.first) { already_added = true; break; }
                            }
                        }
                    }
                }
                if (!already_added) {
                    try {
                        auto d = pair.second.as<BluetoothLEDevice>();
                        flutter::EncodableMap deviceMap = {};
                        deviceMap[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(pair.first);
                        deviceMap[flutter::EncodableValue("platform_name")] = flutter::EncodableValue(utils::to_string(d.Name()));
                        deviceMap[flutter::EncodableValue("connection_state")] = flutter::EncodableValue(1);
                        deviceList.push_back(flutter::EncodableValue(deviceMap));
                    } catch (...) {}
                }
            }
        }


        response[flutter::EncodableValue("devices")] = deviceList;
        co_await ui_thread_;
        result->Success(flutter::EncodableValue(response));
        co_return;
    } catch (const std::exception& e) { error_msg = e.what(); Log("GetSystemDevices Error: %s", error_msg.c_str()); }
      catch (...) { error_msg = "Unknown error occurred"; Log("GetSystemDevices Unknown Error"); }

    if (!error_msg.empty()) {
        co_await ui_thread_;
        result->Error("getSystemDevices", error_msg);
    }
}

// Start() while the watcher is still Stopping reports Started but never
// delivers another advertisement, and that is every restart: flutter_blue_plus
// sends stopScan then startScan back to back, and Stop() only begins the stop.
// A normal stop leaves Stopping in about 10 ms, so wait it out. A watcher
// already wedged that way stays Stopping for good, but Start() from there
// works again, hence the cap.
winrt::fire_and_forget FlutterBluePlusWinrtPlugin::StartScanAsync(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    auto alive = is_alive_;
    for (int i = 0; i < 50 && watcher_.Status() == BluetoothLEAdvertisementWatcherStatus::Stopping; ++i) {
        co_await winrt::resume_after(std::chrono::milliseconds(10));
        co_await ui_thread_;
        if (!*alive) co_return;
    }
    std::string error_msg;
    try {
        scan_results_cache_.clear();
        watcher_.Start();
    } catch (const winrt::hresult_error& e) { error_msg = utils::to_string(e.message()); }
      catch (...) { error_msg = "Unknown error occurred"; }
    if (!error_msg.empty()) {
        result->Error("startScan", error_msg);
        co_return;
    }
    result->Success(flutter::EncodableValue(true));
}

winrt::fire_and_forget FlutterBluePlusWinrtPlugin::GetAdapterStateAsync(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    std::string error_msg;
    try {
        auto radios = co_await Radio::GetRadiosAsync();
        std::string adapter_name = "";
        int adapter_state = 0;
        for (auto radio : radios) {
            if (radio.Kind() != RadioKind::Bluetooth) continue;
            adapter_name = utils::to_string(radio.Name());
            switch (radio.State()) {
            case RadioState::On: adapter_state = 4; break;
            case RadioState::Off: adapter_state = 6; break;
            default: adapter_state = 0; break;
            }
            break;
        }
        flutter::EncodableMap response = {};
        response[flutter::EncodableValue("adapter_state")] = flutter::EncodableValue(adapter_state);
        response[flutter::EncodableValue("adapter_name")] = flutter::EncodableValue(adapter_name);

        co_await ui_thread_;
        result->Success(flutter::EncodableValue(response));
        co_return;
    } catch (const std::exception& e) { error_msg = e.what(); }
      catch (...) { error_msg = "Unknown error occurred"; }

    if (!error_msg.empty()) {
        co_await ui_thread_;
        result->Error("getAdapterState", error_msg);
    }
}

winrt::fire_and_forget FlutterBluePlusWinrtPlugin::GetBondedDevicesAsync(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    std::string error_msg;
    try {
        auto selector = BluetoothDevice::GetDeviceSelectorFromPairingState(true);
        DeviceInformationCollection deviceInfoCollection = co_await DeviceInformation::FindAllAsync(selector);
        flutter::EncodableMap response = {};
        flutter::EncodableList deviceList;

        for (auto&& deviceInfo : deviceInfoCollection) {
            try {
                auto bleDevice = co_await BluetoothLEDevice::FromIdAsync(deviceInfo.Id());
                if (!bleDevice) continue;
                std::string remote_id = uint64_to_mac_string(bleDevice.BluetoothAddress());
                flutter::EncodableMap deviceMap = {};
                deviceMap[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
                deviceMap[flutter::EncodableValue("platform_name")] = flutter::EncodableValue(utils::to_string(deviceInfo.Name()));
                deviceMap[flutter::EncodableValue("connection_state")] = flutter::EncodableValue(bleDevice.ConnectionStatus() == BluetoothConnectionStatus::Connected ? 1 : 0);
                deviceList.push_back(flutter::EncodableValue(deviceMap));
            } catch (...) {}
        }
        response[flutter::EncodableValue("devices")] = deviceList;
        co_await ui_thread_;
        result->Success(flutter::EncodableValue(response));
        co_return;
    } catch (const std::exception& e) { error_msg = e.what(); }
      catch (...) { error_msg = "Unknown error"; }

    if (!error_msg.empty()) {
        co_await ui_thread_;
        result->Error("getBondedDevices", error_msg);
    }
}

winrt::fire_and_forget FlutterBluePlusWinrtPlugin::CreateBondAsync(std::string remote_id, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    std::string error_msg;
    try {
        auto bleDevice = co_await BluetoothLEDevice::FromBluetoothAddressAsync(utils::mac_to_uint64(remote_id));
        if (bleDevice) {
            auto pairing = bleDevice.DeviceInformation().Pairing();
            auto result_val = co_await pairing.PairAsync();
            co_await ui_thread_;
            result->Success(flutter::EncodableValue(result_val.Status() == DevicePairingResultStatus::Paired || result_val.Status() == DevicePairingResultStatus::AlreadyPaired));
            co_return;
        } else {
            error_msg = "Device not found";
        }
    } catch (const std::exception& e) { error_msg = e.what(); }
      catch (...) { error_msg = "Unknown error"; }

    if (!error_msg.empty()) {
        co_await ui_thread_;
        result->Error("createBond", error_msg);
    }
}

winrt::fire_and_forget FlutterBluePlusWinrtPlugin::RemoveBondAsync(std::string remote_id, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    std::string error_msg;
    try {
        auto bleDevice = co_await BluetoothLEDevice::FromBluetoothAddressAsync(utils::mac_to_uint64(remote_id));
        if (bleDevice) {
            auto pairing = bleDevice.DeviceInformation().Pairing();
            auto result_val = co_await pairing.UnpairAsync();
            co_await ui_thread_;
            result->Success(flutter::EncodableValue(result_val.Status() == DeviceUnpairingResultStatus::Unpaired || result_val.Status() == DeviceUnpairingResultStatus::AlreadyUnpaired));
            co_return;
        } else {
            error_msg = "Device not found";
        }
    } catch (const std::exception& e) { error_msg = e.what(); }
      catch (...) { error_msg = "Unknown error"; }

    if (!error_msg.empty()) {
        co_await ui_thread_;
        result->Error("removeBond", error_msg);
    }
}

winrt::fire_and_forget FlutterBluePlusWinrtPlugin::GetBondStateAsync(std::string remote_id, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    std::string error_msg;
    try {
        auto bleDevice = co_await BluetoothLEDevice::FromBluetoothAddressAsync(utils::mac_to_uint64(remote_id));
        if (bleDevice) {
            bool isPaired = bleDevice.DeviceInformation().Pairing().IsPaired();
            flutter::EncodableMap response;
            response[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
            response[flutter::EncodableValue("bond_state")] = flutter::EncodableValue(isPaired ? 2 : 0);
            co_await ui_thread_;
            result->Success(flutter::EncodableValue(response));
            co_return;
        } else {
            error_msg = "Device not found";
        }
    } catch (const std::exception& e) { error_msg = e.what(); }
      catch (...) { error_msg = "Unknown error"; }

    if (!error_msg.empty()) {
        co_await ui_thread_;
        result->Error("getBondState", error_msg);
    }
}

winrt::fire_and_forget FlutterBluePlusWinrtPlugin::ConnectAsync(
    std::string remote_id,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    std::string error_msg;
    try {
        uint64_t bluetoothAddress = utils::mac_to_uint64(remote_id);
        
        co_await ui_thread_;
        
        {
            std::lock_guard<std::mutex> lock(devices_mutex_);
            auto it_existing = std::find_if(connected_devices_.begin(), connected_devices_.end(),
                    [&remote_id](const auto& pair) { return pair.first == remote_id; });
            if (it_existing != connected_devices_.end()) {
                 flutter::EncodableMap connection_state;
                 connection_state[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
                 connection_state[flutter::EncodableValue("connection_state")] = flutter::EncodableValue(1);
                 channel_->InvokeMethod("OnConnectionStateChanged", std::make_unique<flutter::EncodableValue>(connection_state));
                 result->Success(flutter::EncodableValue(true));
                 co_return;
            }
        }

        co_await winrt::resume_background();
        auto device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(bluetoothAddress);
        if (device) {
            co_await ui_thread_;
            {
                std::lock_guard<std::mutex> lock(devices_mutex_);
                auto it = std::find_if(currently_connecting_devices_.begin(), currently_connecting_devices_.end(),
                    [&remote_id](const auto& pair) { return pair.first == remote_id; });
                if (it == currently_connecting_devices_.end()) {
                     currently_connecting_devices_.emplace_back(remote_id, device);
                }
            }
            auto conn_token = device.ConnectionStatusChanged({ this, &FlutterBluePlusWinrtPlugin::OnConnectionStatusChanged });
            {
                std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_);
                connection_tokens_[remote_id] = conn_token;
            }

            co_await winrt::resume_background();
            // Force connection by discovery
            auto gatt_result = co_await device.GetGattServicesAsync(BluetoothCacheMode::Uncached);
            
            // Strictly wait for ConnectionStatus to be Connected (up to 5s)
            int wait_retry = 0;
            while (device.ConnectionStatus() != BluetoothConnectionStatus::Connected && wait_retry < 10) {
                 co_await winrt::resume_after(std::chrono::milliseconds(500));
                 wait_retry++;
            }

            // Windows negotiates the ATT MTU itself; the session is where it
            // shows (MaxPduSize). Without it Dart sees 23 forever.
            // A stale one goes first: FromDeviceIdAsync may hand back the same
            // object, which must not be closed after we take it.
            GattSession session{ nullptr };
            if (gatt_result.Status() == GattCommunicationStatus::Success) {
                { std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_); CloseSessionLocked(remote_id); }
                try { session = co_await GattSession::FromDeviceIdAsync(device.BluetoothDeviceId()); } catch (...) {}
            }
            if (session) {
                try { session.MaintainConnection(true); } catch (...) {}
            }

            co_await ui_thread_;
            
            bool should_close = false;
            bool already_in_connected = false;
            {
                std::lock_guard<std::mutex> lock(devices_mutex_);
                
                // Check if device was already moved to connected_devices_ by OnConnectionStatusChanged
                auto it_connected = std::find_if(connected_devices_.begin(), connected_devices_.end(),
                    [&remote_id](const auto& pair) { return pair.first == remote_id; });
                
                auto it_connecting = std::find_if(currently_connecting_devices_.begin(), currently_connecting_devices_.end(),
                   [&remote_id](const auto& pair) { return pair.first == remote_id; });
                
                // If neither in connected nor connecting list, connection was cancelled/failed
                if (it_connecting == currently_connecting_devices_.end() && it_connected == connected_devices_.end()) {
                    should_close = true;
                } else if (gatt_result.Status() == GattCommunicationStatus::Success && device.ConnectionStatus() == BluetoothConnectionStatus::Connected) {
                     // Ensure device is in connected_devices_ (might already be added by OnConnectionStatusChanged)
                     if (it_connected == connected_devices_.end()) {
                         connected_devices_.emplace_back(remote_id, device);
                     } else {
                         already_in_connected = true;
                     }
                     
                     // Remove from connecting list if still there
                     currently_connecting_devices_.erase(std::remove_if(currently_connecting_devices_.begin(), currently_connecting_devices_.end(),
                        [&remote_id](const auto& pair) { return pair.first == remote_id; }), currently_connecting_devices_.end());
                }
            }
            
            if (should_close) {
                if (device) {
                    { std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_); connection_tokens_.erase(remote_id); }
                    device.Close();
                }
                result->Success(flutter::EncodableValue(false));
                co_return;
            }

            if (gatt_result.Status() == GattCommunicationStatus::Success && device.ConnectionStatus() == BluetoothConnectionStatus::Connected) {
                 // Only send connection state if not already sent by OnConnectionStatusChanged
                 if (!already_in_connected) {
                     flutter::EncodableMap connection_state;
                     connection_state[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
                     connection_state[flutter::EncodableValue("connection_state")] = flutter::EncodableValue(1);
                     channel_->InvokeMethod("OnConnectionStateChanged", std::make_unique<flutter::EncodableValue>(connection_state));
                 }
                 if (session) {
                     auto mtu_token = session.MaxPduSizeChanged([this, remote_id](const GattSession& s, const IInspectable& a) {
                         OnMaxPduSizeChanged(remote_id, s, a);
                     });
                     IInspectable params_request{ nullptr };
#if defined(NTDDI_WIN10_CO) && WDK_NTDDI_VERSION >= NTDDI_WIN10_CO
                     // Windows 11 lets an app ask for a short connection
                     // interval; Windows 10 throws here and keeps its default.
                     try {
                         params_request = device.RequestPreferredConnectionParameters(
                             BluetoothLEPreferredConnectionParameters::Balanced());
                     } catch (...) {}
#endif
                     {
                         std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_);
                         gatt_sessions_[remote_id] = session;
                         mtu_tokens_[remote_id] = mtu_token;
                         if (params_request) connection_params_requests_[remote_id] = params_request;
                     }
                     // The MTU already negotiated, after the connected state so
                     // Dart does not clear it again.
                     OnMaxPduSizeChanged(remote_id, session, nullptr);
                 }
                 result->Success(flutter::EncodableValue(true));
                 co_return;
            } else {
                 std::vector<BluetoothLEDevice> devices_to_close;
                 {
                     std::lock_guard<std::mutex> lock(devices_mutex_);
                     
                     // Check connected devices
                     for (size_t i = 0; i < connected_devices_.size(); ++i) {
                         if (connected_devices_[i].first == remote_id) {
                             devices_to_close.push_back(connected_devices_[i].second.as<BluetoothLEDevice>());
                         }
                     }
                     // Check connecting devices
                     for (size_t i = 0; i < currently_connecting_devices_.size(); ++i) {
                         if (currently_connecting_devices_[i].first == remote_id) {
                             devices_to_close.push_back(currently_connecting_devices_[i].second.as<BluetoothLEDevice>());
                         }
                     }

                     {
                         auto it = connected_devices_.begin();
                         while (it != connected_devices_.end()) {
                             if (it->first == remote_id) {
                                 it = connected_devices_.erase(it);
                             } else {
                                 ++it;
                             }
                         }
                     }

                     {
                         auto it = currently_connecting_devices_.begin();
                         while (it != currently_connecting_devices_.end()) {
                             if (it->first == remote_id) {
                                 it = currently_connecting_devices_.erase(it);
                             } else {
                                 ++it;
                             }
                         }
                     }
                 }
                 
                 { std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_); connection_tokens_.erase(remote_id); }

                 for (auto& d : devices_to_close) {
                     try { d.Close(); } catch(...) {}
                 }

                 flutter::EncodableMap connection_state;
                 connection_state[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
                 connection_state[flutter::EncodableValue("connection_state")] = flutter::EncodableValue(0);
                 channel_->InvokeMethod("OnConnectionStateChanged", std::make_unique<flutter::EncodableValue>(connection_state));

                 result->Success(flutter::EncodableValue(false));
                 co_return;
            }
        } else error_msg = "Device not found.";
    } catch (const std::exception& e) { error_msg = e.what(); }
      catch (...) { error_msg = "Unknown error occurred"; }

    if (!error_msg.empty()) {
        co_await ui_thread_;
        result->Success(flutter::EncodableValue(false));
    }
}

std::string FlutterBluePlusWinrtPlugin::uint64_to_mac_string(uint64_t addr) {
    std::stringstream stream;
    stream << std::hex << std::uppercase << std::setfill('0') << std::setw(2) << ((addr >> 40) & 0xFF) << ":" << std::setw(2) << ((addr >> 32) & 0xFF) << ":" << std::setw(2) << ((addr >> 24) & 0xFF) << ":" << std::setw(2) << ((addr >> 16) & 0xFF) << ":" << std::setw(2) << ((addr >> 8) & 0xFF) << ":" << std::setw(2) << (addr & 0xFF);
    return stream.str();
}

void FlutterBluePlusWinrtPlugin::OnConnectionStatusChanged(const BluetoothLEDevice& device, const IInspectable&) {
    // Capture device by value to avoid dangling references
    [this, alive = is_alive_](BluetoothLEDevice d) -> winrt::fire_and_forget {
        co_await ui_thread_;
        if (!*alive) co_return;

        std::string remote_id = uint64_to_mac_string(d.BluetoothAddress());
        flutter::EncodableMap connection_state;
        connection_state[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);

        if (d.ConnectionStatus() == BluetoothConnectionStatus::Connected) {
             bool solicited = false;
             {
                 std::lock_guard<std::mutex> lock(devices_mutex_);
                 
                 auto it_connected = std::find_if(connected_devices_.begin(), connected_devices_.end(), 
                     [&remote_id](const auto& pair) { return pair.first == remote_id; });
                 
                 if (it_connected != connected_devices_.end()) {
                      solicited = true;
                 } else {
                      auto it_connecting = std::find_if(currently_connecting_devices_.begin(), currently_connecting_devices_.end(), 
                          [&remote_id](const auto& pair) { return pair.first == remote_id; });
                      
                      if(it_connecting != currently_connecting_devices_.end()) {
                           auto dev_obj = it_connecting->second;
                           connected_devices_.emplace_back(remote_id, dev_obj);
                           
                           // Safe removal: use temporary variable to store index to delete
                           currently_connecting_devices_.erase(
                               std::remove_if(currently_connecting_devices_.begin(), currently_connecting_devices_.end(),
                                   [&remote_id](const auto& pair) { return pair.first == remote_id; }
                               ), 
                               currently_connecting_devices_.end()
                           );
                           solicited = true;
                      }
                 }
             }

             if (solicited) {
                connection_state[flutter::EncodableValue("connection_state")] = flutter::EncodableValue(1);
                channel_->InvokeMethod("OnConnectionStateChanged", std::make_unique<flutter::EncodableValue>(connection_state));
             } else {
                Log("Unsolicited connection for %s, closing to prevent unintended auto-reconnect.", remote_id.c_str());
                try { d.Close(); } catch(...) {}
             }
        } else {
            // Disconnection handling - immediately remove from connected list
            Log("OnConnectionStatusChanged: device %s disconnected", remote_id.c_str());
            
            ClearDeviceResources(remote_id);

            {
                std::lock_guard<std::mutex> lock(devices_mutex_);
                
                // Remove device from vectors first
                currently_connecting_devices_.erase(
                    std::remove_if(currently_connecting_devices_.begin(), currently_connecting_devices_.end(),
                        [&remote_id](const auto& pair) { return pair.first == remote_id; }
                    ), 
                    currently_connecting_devices_.end()
                );

                connected_devices_.erase(
                    std::remove_if(connected_devices_.begin(), connected_devices_.end(),
                        [&remote_id](const auto& pair) { return pair.first == remote_id; }
                    ), 
                    connected_devices_.end()
                );
            }
            
            // Close the device - similar to win_ble approach
            try {
                if (d) {
                    d.Close();
                }
            } catch(...) {
                Log("OnConnectionStatusChanged: error closing device %s", remote_id.c_str());
            }

            connection_state[flutter::EncodableValue("connection_state")] = flutter::EncodableValue(0);
            channel_->InvokeMethod("OnConnectionStateChanged", std::make_unique<flutter::EncodableValue>(connection_state));
        }
    }(device);
}

winrt::fire_and_forget FlutterBluePlusWinrtPlugin::DiscoverServicesAsync(
    std::string remote_id,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    auto result_ptr = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
    std::string error_msg;
    try {
        BluetoothLEDevice device = nullptr;

        {
          std::lock_guard<std::mutex> lock(devices_mutex_);
          auto it = std::find_if(connected_devices_.begin(), connected_devices_.end(), [&](const auto& pair) { return pair.first == remote_id; });
          if (it != connected_devices_.end()) device = it->second.as<BluetoothLEDevice>();
        }
        if (!device) { error_msg = "device is disconnected"; }
        else {
            co_await winrt::resume_background();
            // Cached discovery is usually ready immediately after a reconnect;
            // fall back to a full discovery only when the cache is unusable.
            auto servicesResult = co_await device.GetGattServicesAsync(BluetoothCacheMode::Cached);
            if (servicesResult.Status() != GattCommunicationStatus::Success) {
                servicesResult = co_await device.GetGattServicesAsync(BluetoothCacheMode::Uncached);
            }
            if (servicesResult.Status() != GattCommunicationStatus::Success) {
                 error_msg = "GetGattServicesAsync failed";
            } else {
                flutter::EncodableList servicesList;
                for (auto service : servicesResult.Services()) {
                     {
                         std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_);
                         service_cache_[remote_id].push_back(service);
                     }
                     flutter::EncodableMap serviceMap;
                     std::string serviceUuid = utils::to_uuid_string(service.Uuid());
                     serviceMap[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
                     serviceMap[flutter::EncodableValue("service_uuid")] = flutter::EncodableValue(serviceUuid);
                     auto charsList = std::make_shared<flutter::EncodableList>();
                     co_await PopulateCharacteristicsAsync(service, remote_id, "", charsList);
                     serviceMap[flutter::EncodableValue("characteristics")] = *charsList;
                     servicesList.push_back(serviceMap);

                     auto includedResult = co_await service.GetIncludedServicesAsync(BluetoothCacheMode::Cached);
                     if (includedResult.Status() == GattCommunicationStatus::Success) {
                         for (auto includedService : includedResult.Services()) {
                             {
                                 std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_);
                                 service_cache_[remote_id].push_back(includedService);
                             }
                             flutter::EncodableMap includedMap;
                             std::string includedUuid = utils::to_uuid_string(includedService.Uuid());
                             includedMap[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
                             includedMap[flutter::EncodableValue("service_uuid")] = flutter::EncodableValue(includedUuid);
                             includedMap[flutter::EncodableValue("primary_service_uuid")] = flutter::EncodableValue(serviceUuid);
                             auto includedCharsList = std::make_shared<flutter::EncodableList>();
                             co_await PopulateCharacteristicsAsync(includedService, remote_id, serviceUuid, includedCharsList);
                             includedMap[flutter::EncodableValue("characteristics")] = *includedCharsList;
                             servicesList.push_back(includedMap);
                         }
                     }
                }
                flutter::EncodableMap response;
                response[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
                response[flutter::EncodableValue("services")] = servicesList;
                response[flutter::EncodableValue("success")] = flutter::EncodableValue(1);
                response[flutter::EncodableValue("error_code")] = flutter::EncodableValue(0);
                response[flutter::EncodableValue("error_string")] = flutter::EncodableValue("GATT_SUCCESS");
                co_await ui_thread_;
                channel_->InvokeMethod("OnDiscoveredServices", std::make_unique<flutter::EncodableValue>(response));
                result_ptr->Success(flutter::EncodableValue(true));
                co_return;
            }
        }
    } catch (const std::exception& e) { error_msg = e.what(); }
      catch (...) { error_msg = "Unknown error"; }
    
    if (error_msg.empty()) error_msg = "Unknown error";
    co_await ui_thread_;
    result_ptr->Error("discoverServices", error_msg);
}

void FlutterBluePlusWinrtPlugin::OnCharacteristicValueChanged(std::string remote_id, const GattCharacteristic& sender, const GattValueChangedEventArgs& args) {
    [this, remote_id, sender, args, alive = is_alive_]() -> winrt::fire_and_forget {
        try {
            co_await ui_thread_;
            if (!*alive) co_return;
            flutter::EncodableMap response;
            response[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
            response[flutter::EncodableValue("service_uuid")] = flutter::EncodableValue(utils::to_uuid_string(sender.Service().Uuid()));
            response[flutter::EncodableValue("characteristic_uuid")] = flutter::EncodableValue(utils::to_uuid_string(sender.Uuid()));
            response[flutter::EncodableValue("instance_id")] = flutter::EncodableValue(static_cast<int32_t>(sender.AttributeHandle()));
            response[flutter::EncodableValue("value")] = flutter::EncodableValue(utils::to_vector(args.CharacteristicValue()));
            response[flutter::EncodableValue("success")] = flutter::EncodableValue(1);
            response[flutter::EncodableValue("error_code")] = flutter::EncodableValue(0);
            response[flutter::EncodableValue("error_string")] = flutter::EncodableValue("GATT_SUCCESS");
            channel_->InvokeMethod("OnCharacteristicReceived", std::make_unique<flutter::EncodableValue>(response));
        } catch(...) {}
    }();
}

void FlutterBluePlusWinrtPlugin::OnMaxPduSizeChanged(std::string remote_id, const GattSession& sender, const IInspectable&) {
    [this, remote_id, sender, alive = is_alive_]() -> winrt::fire_and_forget {
        try {
            co_await ui_thread_;
            if (!*alive) co_return;
            flutter::EncodableMap response;
            response[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
            response[flutter::EncodableValue("mtu")] = flutter::EncodableValue(static_cast<int32_t>(sender.MaxPduSize()));
            response[flutter::EncodableValue("success")] = flutter::EncodableValue(1);
            response[flutter::EncodableValue("error_code")] = flutter::EncodableValue(0);
            response[flutter::EncodableValue("error_string")] = flutter::EncodableValue("");
            channel_->InvokeMethod("OnMtuChanged", std::make_unique<flutter::EncodableValue>(response));
        } catch(...) {}
    }();
}

winrt::fire_and_forget FlutterBluePlusWinrtPlugin::SetNotifyValueAsync(std::shared_ptr<flutter::EncodableMap> args_ptr) {
    co_await winrt::resume_background();
    flutter::EncodableMap& args = *args_ptr;
    std::string remote_id = utils::from_value<std::string>(&args[flutter::EncodableValue("remote_id")]);
    std::string service_uuid_hint = utils::from_value<std::string>(&args[flutter::EncodableValue("service_uuid")]);
    std::string characteristic_uuid_hint = utils::from_value<std::string>(&args[flutter::EncodableValue("characteristic_uuid")]);
    std::string primary_service_uuid_str = "";
    auto it_primary = args.find(flutter::EncodableValue("primary_service_uuid"));
    if (it_primary != args.end()) primary_service_uuid_str = utils::from_value<std::string>(&it_primary->second);
    int instance_id = utils::from_value<int>(&args[flutter::EncodableValue("instance_id")]);
    bool enable = utils::from_value<bool>(&args[flutter::EncodableValue("enable")]);
    bool force_indications = false;
    auto it_force = args.find(flutter::EncodableValue("force_indications"));
    if (it_force != args.end()) force_indications = utils::from_value<bool>(&it_force->second);

    std::string error_string = "Unknown Error";
    bool success_event = false;
    std::vector<uint8_t> return_value = {0x00, 0x00};
    GattCharacteristic targetChar = nullptr;
    std::string actual_service_uuid = service_uuid_hint;
    std::string actual_char_uuid = characteristic_uuid_hint;

    try {
        BluetoothLEDevice device = nullptr;
        co_await ui_thread_;
        { 
          std::lock_guard<std::mutex> lock(devices_mutex_);
          auto it = std::find_if(connected_devices_.begin(), connected_devices_.end(), [&](const auto& pair) { return pair.first == remote_id; });
          if (it != connected_devices_.end()) device = it->second.as<BluetoothLEDevice>(); 
        }
        co_await winrt::resume_background();
        if (!device) { error_string = "Device not connected"; }
        else {
            targetChar = co_await this->GetCharacteristicInternalAsync(device, remote_id, service_uuid_hint, characteristic_uuid_hint, primary_service_uuid_str, instance_id);
            if (!targetChar) { error_string = "Characteristic not found"; }
            else {
                actual_service_uuid = utils::to_uuid_string(targetChar.Service().Uuid());
                actual_char_uuid = utils::to_uuid_string(targetChar.Uuid());
                std::string token_key = remote_id + ":" + actual_service_uuid + ":" + actual_char_uuid + ":" + std::to_string(instance_id);

                if (enable) {
                    GattClientCharacteristicConfigurationDescriptorValue cccdValue = GattClientCharacteristicConfigurationDescriptorValue::None;
                    auto props = targetChar.CharacteristicProperties();
                    bool canNotify = (static_cast<uint32_t>(props) & static_cast<uint32_t>(GattCharacteristicProperties::Notify)) != 0;
                    bool canIndicate = (static_cast<uint32_t>(props) & static_cast<uint32_t>(GattCharacteristicProperties::Indicate)) != 0;
                    if (force_indications && canIndicate) { cccdValue = GattClientCharacteristicConfigurationDescriptorValue::Indicate; return_value = {0x02, 0x00}; }
                    else if (canNotify) { cccdValue = GattClientCharacteristicConfigurationDescriptorValue::Notify; return_value = {0x01, 0x00}; }
                    else if (canIndicate) { cccdValue = GattClientCharacteristicConfigurationDescriptorValue::Indicate; return_value = {0x02, 0x00}; }
                    else { error_string = "Notify/Indicate not supported"; goto send_event; }

                    GattCommunicationStatus status = GattCommunicationStatus::ProtocolError;
                    try { status = co_await targetChar.WriteClientCharacteristicConfigurationDescriptorAsync(cccdValue); } catch (...) {}
                    if (status != GattCommunicationStatus::Success) {
                        GattDescriptor cccdDescriptor = co_await GetDescriptorAsync(targetChar, "2902");
                        if (cccdDescriptor) {
                            auto writer = winrt::Windows::Storage::Streams::DataWriter();
                            writer.ByteOrder(winrt::Windows::Storage::Streams::ByteOrder::LittleEndian);
                            writer.WriteUInt16((cccdValue == GattClientCharacteristicConfigurationDescriptorValue::Indicate) ? 2 : 1);
                            auto writeResult = co_await cccdDescriptor.WriteValueWithResultAsync(writer.DetachBuffer());
                            status = writeResult.Status();
                        }
                    }

                    if (status != GattCommunicationStatus::Success && (actual_char_uuid == "2a05" || actual_char_uuid == "2A05")) {
                        status = GattCommunicationStatus::Success;
                    }

                    if (status == GattCommunicationStatus::Success) {
                        co_await ui_thread_;
                        std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_);
                        auto it = subscribed_characteristics_.find(token_key);
                        if (it != subscribed_characteristics_.end()) {
                            try { it->second.characteristic.as<GattCharacteristic>().ValueChanged(it->second.token); } catch(...) {}
                            subscribed_characteristics_.erase(it);
                        }
                        auto token = targetChar.ValueChanged([this, remote_id](GattCharacteristic const& sender, GattValueChangedEventArgs const& args) {
                            this->OnCharacteristicValueChanged(remote_id, sender, args);
                        });
                        subscribed_characteristics_[token_key] = { targetChar, token };
                        success_event = true; error_string = "GATT_SUCCESS";
                    } else error_string = "Write CCCD failed: " + std::to_string((int)status);
                } else {
                    return_value = {0x00, 0x00};
                    GattCommunicationStatus status = co_await targetChar.WriteClientCharacteristicConfigurationDescriptorAsync(GattClientCharacteristicConfigurationDescriptorValue::None);
                    if (status == GattCommunicationStatus::Success || actual_char_uuid == "2a05") {
                        co_await ui_thread_;
                        std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_);
                        auto it = subscribed_characteristics_.find(token_key);
                        if (it != subscribed_characteristics_.end()) {
                            try { it->second.characteristic.as<GattCharacteristic>().ValueChanged(it->second.token); } catch(...) {}
                            subscribed_characteristics_.erase(it);
                        }
                        success_event = true; error_string = "GATT_SUCCESS";
                    } else error_string = "Disable CCCD failed";
                }
            }
        }
    } catch (const std::exception& ex) { error_string = ex.what(); }
      catch (...) { error_string = "Unknown Exception"; }

send_event:
    co_await ui_thread_;
    flutter::EncodableMap response;
    response[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
    response[flutter::EncodableValue("primary_service_uuid")] = primary_service_uuid_str.empty() ? flutter::EncodableValue() : flutter::EncodableValue(primary_service_uuid_str);
    response[flutter::EncodableValue("service_uuid")] = flutter::EncodableValue(actual_service_uuid);
    response[flutter::EncodableValue("characteristic_uuid")] = flutter::EncodableValue(actual_char_uuid);
    response[flutter::EncodableValue("descriptor_uuid")] = flutter::EncodableValue("2902");
    response[flutter::EncodableValue("instance_id")] = flutter::EncodableValue(instance_id);
    response[flutter::EncodableValue("value")] = flutter::EncodableValue(return_value);
    response[flutter::EncodableValue("success")] = flutter::EncodableValue(success_event ? 1 : 0);
    response[flutter::EncodableValue("error_code")] = flutter::EncodableValue(success_event ? 0 : 1);
    response[flutter::EncodableValue("error_string")] = flutter::EncodableValue(error_string);
    if (channel_) channel_->InvokeMethod("OnDescriptorWritten", std::make_unique<flutter::EncodableValue>(response));
}

winrt::fire_and_forget FlutterBluePlusWinrtPlugin::ReadCharacteristicAsync(flutter::EncodableMap args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    auto result_ptr = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
    std::string error_msg;
    try {
        std::string remote_id = utils::from_value<std::string>(&args[flutter::EncodableValue("remote_id")]);
        std::string service_uuid_str = utils::from_value<std::string>(&args[flutter::EncodableValue("service_uuid")]);
        std::string characteristic_uuid_str = utils::from_value<std::string>(&args[flutter::EncodableValue("characteristic_uuid")]);
        int instance_id = utils::from_value<int>(&args[flutter::EncodableValue("instance_id")]);
        std::string primary_service_uuid_str = "";
        auto it_primary = args.find(flutter::EncodableValue("primary_service_uuid"));
        if (it_primary != args.end()) primary_service_uuid_str = utils::from_value<std::string>(&it_primary->second);

        BluetoothLEDevice device = nullptr;
        { 
          std::lock_guard<std::mutex> lock(devices_mutex_);
          auto it = std::find_if(connected_devices_.begin(), connected_devices_.end(), [&](const auto& pair) { return pair.first == remote_id; });
          if (it != connected_devices_.end()) device = it->second.as<BluetoothLEDevice>(); 
        }
        if (!device) { error_msg = "device is disconnected"; }
        else {
            co_await winrt::resume_background();
            GattCharacteristic targetChar = co_await this->GetCharacteristicInternalAsync(device, remote_id, service_uuid_str, characteristic_uuid_str, primary_service_uuid_str, instance_id);
            if (!targetChar) { error_msg = "Characteristic not found"; }
            else {
                auto readResult = co_await targetChar.ReadValueAsync(BluetoothCacheMode::Uncached);
                if (readResult.Status() == GattCommunicationStatus::Success) {
                    flutter::EncodableMap response;
                    response[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
                    response[flutter::EncodableValue("service_uuid")] = flutter::EncodableValue(service_uuid_str);
                    response[flutter::EncodableValue("characteristic_uuid")] = flutter::EncodableValue(characteristic_uuid_str);
                    response[flutter::EncodableValue("instance_id")] = flutter::EncodableValue(instance_id);
                    response[flutter::EncodableValue("value")] = flutter::EncodableValue(utils::to_vector(readResult.Value()));
                    response[flutter::EncodableValue("success")] = flutter::EncodableValue(1);
                    response[flutter::EncodableValue("error_code")] = flutter::EncodableValue(0);
                    response[flutter::EncodableValue("error_string")] = flutter::EncodableValue("GATT_SUCCESS");
                    co_await ui_thread_;
                    channel_->InvokeMethod("OnCharacteristicReceived", std::make_unique<flutter::EncodableValue>(response));
                    result_ptr->Success(flutter::EncodableValue(true));
                    co_return;
                } else { error_msg = "Read failed: " + std::to_string((int)readResult.Status()); }
            }
        }
    } catch (const std::exception& e) { error_msg = e.what(); }
      catch (...) { error_msg = "Unknown error"; }

    co_await ui_thread_;
    result_ptr->Error("readCharacteristic", error_msg);
}

winrt::fire_and_forget FlutterBluePlusWinrtPlugin::WriteCharacteristicAsync(flutter::EncodableMap args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    auto result_ptr = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
    std::string error_msg;
    try {
        std::string remote_id = utils::from_value<std::string>(&args[flutter::EncodableValue("remote_id")]);
        std::string service_uuid_str = utils::from_value<std::string>(&args[flutter::EncodableValue("service_uuid")]);
        std::string characteristic_uuid_str = utils::from_value<std::string>(&args[flutter::EncodableValue("characteristic_uuid")]);
        int instance_id = utils::from_value<int>(&args[flutter::EncodableValue("instance_id")]);
        std::vector<uint8_t> value = utils::from_value<std::vector<uint8_t>>(&args[flutter::EncodableValue("value")]);
        int write_type = utils::from_value<int>(&args[flutter::EncodableValue("write_type")]);
        std::string primary_service_uuid_str = "";
        auto it_primary = args.find(flutter::EncodableValue("primary_service_uuid"));
        if (it_primary != args.end()) primary_service_uuid_str = utils::from_value<std::string>(&it_primary->second);

        BluetoothLEDevice device = nullptr;
        { 
          std::lock_guard<std::mutex> lock(devices_mutex_);
          auto it = std::find_if(connected_devices_.begin(), connected_devices_.end(), [&](const auto& pair) { return pair.first == remote_id; });
          if (it != connected_devices_.end()) device = it->second.as<BluetoothLEDevice>(); 
        }
        if (!device) { error_msg = "device is disconnected"; }
        else {
            co_await winrt::resume_background();
            GattCharacteristic targetChar = co_await this->GetCharacteristicInternalAsync(device, remote_id, service_uuid_str, characteristic_uuid_str, primary_service_uuid_str, instance_id);
            if (!targetChar) { error_msg = "Characteristic not found"; }
            else {
                auto writer = winrt::Windows::Storage::Streams::DataWriter();
                writer.WriteBytes(value);
                GattWriteOption option = (write_type == 1) ? GattWriteOption::WriteWithoutResponse : GattWriteOption::WriteWithResponse;
                auto writeOp = targetChar.WriteValueWithResultAsync(writer.DetachBuffer(), option);
                // Without response, answer as soon as the stack has the packet,
                // as Android and Darwin do. Awaiting the send held the next
                // write back a connection event or more (Win10 FOTA ~8KB/s).
                // Order holds: the next write starts after this call returned.
                // A failed send goes unreported, as on the other platforms.
                GattCommunicationStatus status = GattCommunicationStatus::Success;
                if (write_type != 1) status = (co_await writeOp).Status();

                co_await ui_thread_;
                flutter::EncodableMap response;
                response[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
                response[flutter::EncodableValue("service_uuid")] = flutter::EncodableValue(service_uuid_str);
                response[flutter::EncodableValue("characteristic_uuid")] = flutter::EncodableValue(characteristic_uuid_str);
                response[flutter::EncodableValue("instance_id")] = flutter::EncodableValue(instance_id);
                response[flutter::EncodableValue("value")] = flutter::EncodableValue(value);
                response[flutter::EncodableValue("success")] = flutter::EncodableValue(status == GattCommunicationStatus::Success ? 1 : 0);
                response[flutter::EncodableValue("error_code")] = flutter::EncodableValue((int)status);
                response[flutter::EncodableValue("error_string")] = flutter::EncodableValue(status == GattCommunicationStatus::Success ? "GATT_SUCCESS" : "Write failed");
                channel_->InvokeMethod("OnCharacteristicWritten", std::make_unique<flutter::EncodableValue>(response));
                result_ptr->Success(flutter::EncodableValue(true));
                co_return;
            }
        }
    } catch (const std::exception& e) { error_msg = e.what(); }
      catch (...) { error_msg = "Unknown error"; }

    co_await ui_thread_;
    result_ptr->Error("writeCharacteristic", error_msg);
}

winrt::fire_and_forget FlutterBluePlusWinrtPlugin::ReadDescriptorAsync(flutter::EncodableMap args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    auto result_ptr = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
    std::string error_msg;
    try {
        std::string remote_id = utils::from_value<std::string>(&args[flutter::EncodableValue("remote_id")]);
        std::string service_uuid_hint = utils::from_value<std::string>(&args[flutter::EncodableValue("service_uuid")]);
        std::string characteristic_uuid_hint = utils::from_value<std::string>(&args[flutter::EncodableValue("characteristic_uuid")]);
        std::string descriptor_uuid_hint = utils::from_value<std::string>(&args[flutter::EncodableValue("descriptor_uuid")]);
        int instance_id = utils::from_value<int>(&args[flutter::EncodableValue("instance_id")]);
        std::string primary_service_uuid_str = "";
        auto it_primary = args.find(flutter::EncodableValue("primary_service_uuid"));
        if (it_primary != args.end()) primary_service_uuid_str = utils::from_value<std::string>(&it_primary->second);

        BluetoothLEDevice device = nullptr;
        { 
          std::lock_guard<std::mutex> lock(devices_mutex_);
          auto it = std::find_if(connected_devices_.begin(), connected_devices_.end(), [&](const auto& pair) { return pair.first == remote_id; });
          if (it != connected_devices_.end()) device = it->second.as<BluetoothLEDevice>(); 
        }
        if (!device) { error_msg = "device is disconnected"; }
        else {
            co_await winrt::resume_background();

            GattDescriptor targetDesc = nullptr;
            if (instance_id != 0) {
                std::string d_key = remote_id + ":" + std::to_string(instance_id);
                std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_);
                auto it_d = descriptor_cache_.find(d_key);
                if (it_d != descriptor_cache_.end()) targetDesc = it_d->second.as<GattDescriptor>();
            }

            if (!targetDesc) {
                GattCharacteristic targetChar = co_await this->GetCharacteristicByDescriptorHandleAsync(device, instance_id);
                if (!targetChar) {
                    targetChar = co_await this->GetCharacteristicInternalAsync(device, remote_id, service_uuid_hint, characteristic_uuid_hint, primary_service_uuid_str, instance_id);
                }

                if (targetChar) {
                    targetDesc = co_await GetDescriptorAsync(targetChar, descriptor_uuid_hint);
                }
            }

            if (!targetDesc) { error_msg = "Descriptor not found"; }
            else {
                auto readResult = co_await targetDesc.ReadValueAsync(BluetoothCacheMode::Uncached);
                if (readResult.Status() == GattCommunicationStatus::Success) {
                    flutter::EncodableMap response;
                    response[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
                    response[flutter::EncodableValue("primary_service_uuid")] = primary_service_uuid_str.empty() ? flutter::EncodableValue() : flutter::EncodableValue(primary_service_uuid_str);
                    response[flutter::EncodableValue("service_uuid")] = flutter::EncodableValue(service_uuid_hint);
                    response[flutter::EncodableValue("characteristic_uuid")] = flutter::EncodableValue(characteristic_uuid_hint);
                    response[flutter::EncodableValue("descriptor_uuid")] = flutter::EncodableValue(utils::to_uuid_string(targetDesc.Uuid()));
                    response[flutter::EncodableValue("instance_id")] = flutter::EncodableValue(instance_id);
                    response[flutter::EncodableValue("value")] = flutter::EncodableValue(utils::to_vector(readResult.Value()));
                    response[flutter::EncodableValue("success")] = flutter::EncodableValue(1);
                    response[flutter::EncodableValue("error_code")] = flutter::EncodableValue(0);
                    response[flutter::EncodableValue("error_string")] = flutter::EncodableValue("GATT_SUCCESS");
                    
                    co_await ui_thread_;
                    channel_->InvokeMethod("OnDescriptorRead", std::make_unique<flutter::EncodableValue>(response));
                    result_ptr->Success(flutter::EncodableValue(true));
                    co_return;
                } else { error_msg = "Read failed: " + std::to_string((int)readResult.Status()); }
            }
        }
    } catch (const std::exception& e) { error_msg = e.what(); }
      catch (...) { error_msg = "Unknown error"; }

    co_await ui_thread_;
    result_ptr->Error("readDescriptor", error_msg);
}

winrt::fire_and_forget FlutterBluePlusWinrtPlugin::WriteDescriptorAsync(flutter::EncodableMap args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    auto result_ptr = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
    std::string error_msg;
    try {
        std::string remote_id = utils::from_value<std::string>(&args[flutter::EncodableValue("remote_id")]);
        std::string service_uuid_hint = utils::from_value<std::string>(&args[flutter::EncodableValue("service_uuid")]);
        std::string characteristic_uuid_hint = utils::from_value<std::string>(&args[flutter::EncodableValue("characteristic_uuid")]);
        std::string descriptor_uuid_hint = utils::from_value<std::string>(&args[flutter::EncodableValue("descriptor_uuid")]);
        std::vector<uint8_t> value = utils::from_value<std::vector<uint8_t>>(&args[flutter::EncodableValue("value")]);
        int instance_id = utils::from_value<int>(&args[flutter::EncodableValue("instance_id")]);
        std::string primary_service_uuid_str = "";
        auto it_primary = args.find(flutter::EncodableValue("primary_service_uuid"));
        if (it_primary != args.end()) primary_service_uuid_str = utils::from_value<std::string>(&it_primary->second);

        BluetoothLEDevice device = nullptr;
        { 
          std::lock_guard<std::mutex> lock(devices_mutex_);
          auto it = std::find_if(connected_devices_.begin(), connected_devices_.end(), [&](const auto& pair) { return pair.first == remote_id; });
          if (it != connected_devices_.end()) device = it->second.as<BluetoothLEDevice>(); 
        }
        if (!device) { error_msg = "device is disconnected"; }
        else {
            co_await winrt::resume_background();
            
            GattDescriptor targetDesc = nullptr;
            if (instance_id != 0) {
                std::string d_key = remote_id + ":" + std::to_string(instance_id);
                std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_);
                auto it_d = descriptor_cache_.find(d_key);
                if (it_d != descriptor_cache_.end()) targetDesc = it_d->second.as<GattDescriptor>();
            }

            if (!targetDesc) {
                GattCharacteristic targetChar = co_await this->GetCharacteristicInternalAsync(device, remote_id, service_uuid_hint, characteristic_uuid_hint, primary_service_uuid_str, instance_id);
                if (targetChar) {
                    targetDesc = co_await GetDescriptorAsync(targetChar, descriptor_uuid_hint);
                }
            }

            if (!targetDesc) { error_msg = "Descriptor not found"; }
            else {
                auto writer = winrt::Windows::Storage::Streams::DataWriter();
                writer.WriteBytes(value);
                auto writeResult = co_await targetDesc.WriteValueWithResultAsync(writer.DetachBuffer());
                if (writeResult.Status() == GattCommunicationStatus::Success) {
                    flutter::EncodableMap response;
                    response[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
                    response[flutter::EncodableValue("primary_service_uuid")] = primary_service_uuid_str.empty() ? flutter::EncodableValue() : flutter::EncodableValue(primary_service_uuid_str);
                    response[flutter::EncodableValue("service_uuid")] = flutter::EncodableValue(service_uuid_hint);
                    response[flutter::EncodableValue("characteristic_uuid")] = flutter::EncodableValue(characteristic_uuid_hint);
                    response[flutter::EncodableValue("descriptor_uuid")] = flutter::EncodableValue(utils::to_uuid_string(targetDesc.Uuid()));
                    response[flutter::EncodableValue("instance_id")] = flutter::EncodableValue(instance_id);
                    response[flutter::EncodableValue("value")] = flutter::EncodableValue(value);
                    response[flutter::EncodableValue("success")] = flutter::EncodableValue(1);
                    response[flutter::EncodableValue("error_code")] = flutter::EncodableValue(0);
                    response[flutter::EncodableValue("error_string")] = flutter::EncodableValue("GATT_SUCCESS");
                    
                    co_await ui_thread_;
                    channel_->InvokeMethod("OnDescriptorWritten", std::make_unique<flutter::EncodableValue>(response));
                    result_ptr->Success(flutter::EncodableValue(true));
                    co_return;
                } else { error_msg = "Write failed: " + std::to_string((int)writeResult.Status()); }
            }
        }
    } catch (const std::exception& e) { error_msg = e.what(); }
      catch (...) { error_msg = "Unknown error"; }

    co_await ui_thread_;
    result_ptr->Error("writeDescriptor", error_msg);
}

void FlutterBluePlusWinrtPlugin::CloseSessionLocked(const std::string& remote_id) {
    auto it_gs = gatt_sessions_.find(remote_id);
    if (it_gs != gatt_sessions_.end()) {
        try {
            auto session = it_gs->second.as<GattSession>();
            auto it_mtu = mtu_tokens_.find(remote_id);
            if (it_mtu != mtu_tokens_.end()) session.MaxPduSizeChanged(it_mtu->second);
            session.Close();
        } catch(...) {}
        gatt_sessions_.erase(it_gs);
    }
    mtu_tokens_.erase(remote_id);

    auto it_cp = connection_params_requests_.find(remote_id);
    if (it_cp != connection_params_requests_.end()) {
        try { it_cp->second.as<winrt::Windows::Foundation::IClosable>().Close(); } catch(...) {}
        connection_params_requests_.erase(it_cp);
    }
}

void FlutterBluePlusWinrtPlugin::ClearDeviceResources(std::string remote_id) {
    // Guards every cache touched below against concurrent background-thread
    // access (service discovery / read / write). This function performs no
    // co_await, so holding the lock for its whole body is safe.
    std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_);

    for (auto it = subscribed_characteristics_.begin(); it != subscribed_characteristics_.end(); ) {
        if (it->first.find(remote_id) == 0) {
            try {
                auto characteristic = it->second.characteristic.as<GattCharacteristic>();
                if (characteristic) characteristic.ValueChanged(it->second.token);
            } catch (...) {}
            it = subscribed_characteristics_.erase(it);
        } else {
            ++it;
        }
    }

    for (auto it = characteristic_cache_.begin(); it != characteristic_cache_.end(); ) {
        if (it->first.find(remote_id) == 0) it = characteristic_cache_.erase(it);
        else ++it;
    }
    for (auto it = descriptor_cache_.begin(); it != descriptor_cache_.end(); ) {
        if (it->first.find(remote_id) == 0) it = descriptor_cache_.erase(it);
        else ++it;
    }

    auto it_s = service_cache_.find(remote_id);
    if (it_s != service_cache_.end()) {
        for (auto& inspectable : it_s->second) {
            try {
                auto service = inspectable.as<GattDeviceService>();
                if (service) service.Close();
            } catch (...) {}
        }
        service_cache_.erase(it_s);
    }
    
    CloseSessionLocked(remote_id);

    rssi_cache_.erase(remote_id);

    // The device is Closed by the caller in the same disconnect flow, so the
    // handler stops firing; just drop the token entry to keep the map bounded.
    connection_tokens_.erase(remote_id);
}

winrt::fire_and_forget FlutterBluePlusWinrtPlugin::PeriodicConnectionCheck() {
    // Copy the shared alive flag into the coroutine frame so it stays valid even
    // after the plugin object is destroyed. Check it right after every resume,
    // before touching any `this` member.
    auto alive = is_alive_;
    while (*alive) {
        co_await winrt::resume_after(winrt::Windows::Foundation::TimeSpan(20000000));
        if (!*alive) co_return;
        co_await ui_thread_;
        if (!*alive) co_return;

        std::vector<std::string> mac_to_remove;
        {
            std::lock_guard<std::mutex> lock(devices_mutex_);
            for (size_t i = 0; i < connected_devices_.size(); ++i) {
                const auto& pair = connected_devices_[i];
                std::string remote_id = pair.first;
                auto device = pair.second.as<BluetoothLEDevice>();
                bool is_connected = false;
                try { if (device) is_connected = (device.ConnectionStatus() == BluetoothConnectionStatus::Connected); } catch (...) {}
                if (!is_connected) {
                    Log("PeriodicCheck: Device %s disconnected, marking for removal.", remote_id.c_str());
                    mac_to_remove.push_back(remote_id);
                }
            }
        }

        for (const auto& remote_id : mac_to_remove) {
            ClearDeviceResources(remote_id);
            if (channel_) {
                flutter::EncodableMap connection_state;
                connection_state[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
                connection_state[flutter::EncodableValue("connection_state")] = flutter::EncodableValue(0); 
                channel_->InvokeMethod("OnConnectionStateChanged", std::make_unique<flutter::EncodableValue>(connection_state));
            }
            
            std::vector<BluetoothLEDevice> to_close;
            {
                std::lock_guard<std::mutex> lock(devices_mutex_);
                auto it = connected_devices_.begin();
                while (it != connected_devices_.end()) {
                    if (it->first == remote_id) {
                        try { auto d = it->second.as<BluetoothLEDevice>(); if (d) to_close.push_back(d); } catch(...) {}
                        it = connected_devices_.erase(it);
                    } else {
                        ++it;
                    }
                }
            }
            
            for (auto& d : to_close) { try { d.Close(); } catch(...) {} }
        }
    }
}

void FlutterBluePlusWinrtPlugin::HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& method_call, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const auto& method = method_call.method_name();
    if (method == "flutterRestart") {
        int count = 0;
        watcher_.Stop();

        std::vector<BluetoothLEDevice> to_close;
        std::vector<std::string> devices_to_clear;
        {
            std::lock_guard<std::mutex> lock(devices_mutex_);
            count = static_cast<int>(connected_devices_.size());
            
            for (size_t i = 0; i < connected_devices_.size(); ++i) {
                const auto& pair = connected_devices_[i];
                try { if (auto device = pair.second.as<BluetoothLEDevice>()) to_close.push_back(device); } catch(...) {}
                devices_to_clear.push_back(pair.first);
            }
            for (size_t i = 0; i < currently_connecting_devices_.size(); ++i) {
                const auto& pair = currently_connecting_devices_[i];
                try { if (auto device = pair.second.as<BluetoothLEDevice>()) to_close.push_back(device); } catch(...) {}
            }
            
            connected_devices_.clear(); 
            currently_connecting_devices_.clear();
        }
        
        for (const auto& remote_id : devices_to_clear) {
            ClearDeviceResources(remote_id);
        }
        
        {
            std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_);
            rssi_cache_.clear();
            scan_results_cache_.clear();
            subscribed_characteristics_.clear();
            characteristic_cache_.clear();
            descriptor_cache_.clear();
            service_cache_.clear();
        }

        for (auto& d : to_close) { try { d.Close(); } catch(...) {} }

        result->Success(flutter::EncodableValue(count)); return;
    }
    if (method == "startScan") { StartScanAsync(std::move(result)); return; }
    if (method == "stopScan") { watcher_.Stop(); result->Success(flutter::EncodableValue(true)); return; }
    if (method == "getSystemDevices") { GetSystemDevicesAsync(std::move(result)); return; }
    if (method == "getAdapterState") { GetAdapterStateAsync(std::move(result)); return; }
    if (method == "connect") {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        std::string remote_id = ""; if (args) { auto it = args->find(flutter::EncodableValue("remote_id")); if (it != args->end()) remote_id = utils::from_value<std::string>(&it->second); }
        ConnectAsync(remote_id, std::move(result)); return;
    }
    if (method == "disconnect") {
        const auto* remote_id_val_ptr = std::get_if<std::string>(method_call.arguments());
        if (remote_id_val_ptr) {
            std::string remote_id = *remote_id_val_ptr;
            
            std::vector<BluetoothLEDevice> to_close;
            
            {
                std::lock_guard<std::mutex> lock(devices_mutex_);
                {
                    auto it = currently_connecting_devices_.begin();
                    while (it != currently_connecting_devices_.end()) {
                        if (it->first == remote_id) {
                            try { if (auto device = it->second.as<BluetoothLEDevice>()) to_close.push_back(device); } catch(...) {}
                            it = currently_connecting_devices_.erase(it);
                        } else {
                            ++it;
                        }
                    }
                }

                {
                    auto it = connected_devices_.begin();
                    while (it != connected_devices_.end()) {
                        if (it->first == remote_id) {
                            try { if (auto device = it->second.as<BluetoothLEDevice>()) to_close.push_back(device); } catch(...) {}
                            it = connected_devices_.erase(it);
                        } else {
                            ++it;
                        }
                    }
                }
            }

            for (auto& d : to_close) { try { d.Close(); } catch(...) {} }

            ClearDeviceResources(remote_id);

            flutter::EncodableMap connection_state; connection_state[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id); connection_state[flutter::EncodableValue("connection_state")] = flutter::EncodableValue(0); 
            channel_->InvokeMethod("OnConnectionStateChanged", std::make_unique<flutter::EncodableValue>(connection_state));
        }
        result->Success(flutter::EncodableValue(true)); return;
    }
    if (method == "discoverServices") {
        const auto* remote_id_val = std::get_if<std::string>(method_call.arguments());
        if (remote_id_val) DiscoverServicesAsync(*remote_id_val, std::move(result));
        else result->Error("discoverServices", "Invalid arguments");
        return;
    }
    if (method == "setNotifyValue") {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args) { auto args_ptr = std::make_shared<flutter::EncodableMap>(*args); result->Success(flutter::EncodableValue(true)); SetNotifyValueAsync(args_ptr); }
        else result->Error("setNotifyValue", "Invalid arguments");
        return;
    }
    if (method == "readCharacteristic") {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args) ReadCharacteristicAsync(*args, std::move(result)); else result->Error("readCharacteristic", "Invalid arguments");
        return;
    }
    if (method == "writeCharacteristic") {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args) WriteCharacteristicAsync(*args, std::move(result)); else result->Error("writeCharacteristic", "Invalid arguments");
        return;
    }
    if (method == "readDescriptor") {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args) ReadDescriptorAsync(*args, std::move(result)); else result->Error("readDescriptor", "Invalid arguments");
        return;
    }
    if (method == "writeDescriptor") {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args) WriteDescriptorAsync(*args, std::move(result)); else result->Error("writeDescriptor", "Invalid arguments");
        return;
    }
    if (method == "setLogLevel") { result->Success(flutter::EncodableValue(true)); return; }
    if (method == "setOptions") { result->Success(flutter::EncodableValue(true)); return; }
    if (method == "isSupported") { result->Success(flutter::EncodableValue(true)); return; }
    if (method == "requestMtu") {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        std::string remote_id = "";
        if (args) {
            auto it = args->find(flutter::EncodableValue("remote_id"));
            if (it != args->end()) remote_id = utils::from_value<std::string>(&it->second);
        }
        if (!remote_id.empty()) {
            winrt::Windows::Foundation::IInspectable session_obj = nullptr;
            {
                std::lock_guard<std::mutex> cache_lock(gatt_cache_mutex_);
                auto it = gatt_sessions_.find(remote_id);
                if (it != gatt_sessions_.end()) session_obj = it->second;
            }
            if (session_obj) {
                auto session = session_obj.as<GattSession>();
                flutter::EncodableMap response;
                response[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
                response[flutter::EncodableValue("mtu")] = flutter::EncodableValue(static_cast<int32_t>(session.MaxPduSize()));
                response[flutter::EncodableValue("success")] = flutter::EncodableValue(1);
                response[flutter::EncodableValue("error_code")] = flutter::EncodableValue(0);
                response[flutter::EncodableValue("error_string")] = flutter::EncodableValue("");
                channel_->InvokeMethod("OnMtuChanged", std::make_unique<flutter::EncodableValue>(response));
            }
        }
        result->Success(flutter::EncodableValue(true));
        return;
    }
    if (method == "requestConnectionPriority") { result->Success(flutter::EncodableValue(true)); return; }
    if (method == "setPreferredPhy") { result->Success(flutter::EncodableValue(true)); return; }
    if (method == "turnOn") { result->Success(flutter::EncodableValue(false)); return; }
    if (method == "turnOff") { result->Success(flutter::EncodableValue(false)); return; }
    if (method == "clearGattCache") { result->Success(flutter::EncodableValue(true)); return; }
    if (method == "getPhySupport") { 
        flutter::EncodableMap response;
        response[flutter::EncodableValue("le_2m")] = flutter::EncodableValue(true);
        response[flutter::EncodableValue("le_coded")] = flutter::EncodableValue(true);
        result->Success(flutter::EncodableValue(response)); 
        return; 
    }
    if (method == "createBond") {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        std::string remote_id = ""; if (args) { auto it = args->find(flutter::EncodableValue("remote_id")); if (it != args->end()) remote_id = utils::from_value<std::string>(&it->second); }
        CreateBondAsync(remote_id, std::move(result)); return;
    }
    if (method == "removeBond") {
        const auto* remote_id_val = std::get_if<std::string>(method_call.arguments());
        if (remote_id_val) RemoveBondAsync(*remote_id_val, std::move(result));
        else result->Error("removeBond", "Invalid arguments");
        return;
    }
    if (method == "getBondState") {
        const auto* remote_id_val = std::get_if<std::string>(method_call.arguments());
        if (remote_id_val) GetBondStateAsync(*remote_id_val, std::move(result));
        else result->Error("getBondState", "Invalid arguments");
        return;
    }
    if (method == "getBondedDevices") {
        GetBondedDevicesAsync(std::move(result));
        return;
    }
    if (method == "connectedCount") { 
        int count = 0;
        {
            std::lock_guard<std::mutex> lock(devices_mutex_);
            count = static_cast<int>(connected_devices_.size());
        }
        result->Success(flutter::EncodableValue(count)); 
        return; 
    }
    if (method == "readRssi") {
        const auto* remote_id_arg = std::get_if<std::string>(method_call.arguments());
        if (remote_id_arg) {
            std::string remote_id = *remote_id_arg;
            flutter::EncodableMap rssi_result;
            rssi_result[flutter::EncodableValue("remote_id")] = flutter::EncodableValue(remote_id);
            rssi_result[flutter::EncodableValue("error_code")] = flutter::EncodableValue(0);
            rssi_result[flutter::EncodableValue("error_string")] = flutter::EncodableValue("GATT_SUCCESS");
            
            auto it = rssi_cache_.find(remote_id);
            if (it != rssi_cache_.end()) {
                rssi_result[flutter::EncodableValue("rssi")] = flutter::EncodableValue(it->second);
            } else {
                rssi_result[flutter::EncodableValue("rssi")] = flutter::EncodableValue(0);
            }
            rssi_result[flutter::EncodableValue("success")] = flutter::EncodableValue(1);
            rssi_result[flutter::EncodableValue("error_code")] = flutter::EncodableValue(0);
            rssi_result[flutter::EncodableValue("error_string")] = flutter::EncodableValue("GATT_SUCCESS");
            channel_->InvokeMethod("OnReadRssi", std::make_unique<flutter::EncodableValue>(rssi_result));
            result->Success(flutter::EncodableValue(true));
        } else result->Error("readRssi", "Invalid arguments");
        return;
    }

    result->NotImplemented();
}

}  // namespace flutter_blue_plus_winrt
