require 'fog/google'

module ManageIQ::Providers
  module Google
    class CloudManager::RefreshParser < ManageIQ::Providers::CloudManager::RefreshParser
      include Vmdb::Logging

      def self.ems_inv_to_hashes(ems, options = nil)
        new(ems, options).ems_inv_to_hashes
      end

      def initialize(ems, options = nil)
        @ems               = ems
        @connection        = ems.connect
        @options           = options || {}
        @data              = {}
        @data_index        = {}
      end

      def ems_inv_to_hashes
        log_header = "Collecting data for EMS : [#{@ems.name}] id: [#{@ems.id}]"

        _log.info("#{log_header}...")
        get_zones
        get_images
        get_instances
        _log.info("#{log_header}...Complete")

        @data
      end

      private

      def get_zones
        zones = @connection.zones.all
        process_collection(zones, :availability_zones) { |zone| parse_zone(zone) }
      end

      def get_images
        images = @connection.images.all
        process_collection(images, :vms) { |image| parse_image(image) }
      end

      def get_instances
        instances = @connection.servers.all
        process_collection(instances, :vms) { |instance| parse_instance(instance) }
      end

      def process_collection(collection, key)
        @data[key] ||= []

        collection.each do |item|
          uid, new_result = yield(item)
          next if uid.nil?

          @data[key] << new_result
          @data_index.store_path(key, uid, new_result)
        end
      end

      def parse_zone(zone)
        name = uid = zone.name
        type = ManageIQ::Providers::Google::CloudManager::AvailabilityZone.name

        new_result = {
          :type    => type,
          :ems_ref => uid,
          :name    => name,
        }

        return uid, new_result
      end

      def parse_image(image)
        uid    = image.id
        name   = image.name
        name ||= uid
        type   = ManageIQ::Providers::Google::CloudManager::Template.name

        new_result = {
          :type               => type,
          :uid_ems            => uid,
          :ems_ref            => uid,
          :name               => name,
          :vendor             => "google",
          :raw_power_state    => "never",
          :template           => true,
          :publicly_available => true,
        }

        return uid, new_result
      end

      def parse_instance(instance)
        uid    = instance.id
        name   = instance.name
        name ||= uid

        zone_uid   = parse_uid_from_url(instance.zone)
        zone       = @data_index.fetch_path(:availability_zones, zone_uid)

        type = ManageIQ::Providers::Google::CloudManager::Vm.name
        new_result = {
          :type              => type,
          :uid_ems           => uid,
          :ems_ref           => uid,
          :name              => name,
          :description       => instance.description,
          :vendor            => "google",
          :raw_power_state   => instance.state,
          :availability_zone => zone,
        }

        return uid, new_result
      end

      def parse_uid_from_url(url)
        # A lot of attributes in gce are full URLs with the
        # uid being the last component.  This helper method
        # returns the last component of the url
        uid = url.split('/')[-1]
        uid
      end
    end
  end
end