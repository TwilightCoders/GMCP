# frozen_string_literal: true

module GMCP
  module Voice
    class Message
      ATTRS = %w[
        id phoneNumber displayNumber startTime displayStartDateTime
        relativeStartTime isRead isTrash isSpam star note labels type children
      ].freeze

      attr_reader(*ATTRS.map(&:to_sym), :type_name)

      def initialize(session, id, data)
        @session = session
        @id      = id
        ATTRS.each { |a| instance_variable_set(:"@#{a}", data[a]) }
        @type_name = MESSAGE_TYPES[@type.to_i]
      end

      def delete!(trash: true)
        @session.post(OPERATION_URLS[:delete], 'messages' => @id, 'trash' => trash ? '1' : '0')
      end

      def archive!
        @session.post(OPERATION_URLS[:archive], 'messages' => @id, 'archive' => '1')
      end

      def mark_read!(read: true)
        @session.post(OPERATION_URLS[:mark], 'messages' => @id, 'read' => read ? '1' : '0')
      end

      def star!(star: true)
        @session.post(OPERATION_URLS[:star], 'messages' => @id, 'star' => star ? '1' : '0')
      end

      def to_s
        @id.to_s
      end

      def inspect
        "#<Voice::Message #{@id} #{@type_name} from=#{@displayNumber}>"
      end

      def to_h
        ATTRS.each_with_object({}) { |a, h| h[a] = instance_variable_get(:"@#{a}") }
      end
    end
  end
end
