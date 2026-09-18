// GERADO AUTOMATICAMENTE - nao edite a mao.
//
// Origem: o schema real do Postgres, lido por scripts/gerar-tipos.mjs.
// Para atualizar depois de uma migracao:  npm run db:tipos
//
// Tabelas: 32   Enums: 14   Funcoes: 8

export type Json = string | number | boolean | null | { [chave: string]: Json | undefined } | Json[]

export interface Database {
  public: {
    Tables: {
      addon_groups: {
        Row: {
          id: string
          restaurant_id: string
          product_id: string
          name: string
          description: string | null
          is_required: boolean
          min_select: number
          max_select: number
          position: number
          is_active: boolean
          created_at: string
          updated_at: string
          deleted_at: string | null
        }
        Insert: {
          id?: string
          restaurant_id: string
          product_id: string
          name: string
          description?: string | null
          is_required?: boolean
          min_select?: number
          max_select?: number
          position?: number
          is_active?: boolean
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
        }
        Update: {
          id?: string
          restaurant_id?: string
          product_id?: string
          name?: string
          description?: string | null
          is_required?: boolean
          min_select?: number
          max_select?: number
          position?: number
          is_active?: boolean
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "addon_groups_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "addon_groups_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          }
        ]
      }
      addons: {
        Row: {
          id: string
          restaurant_id: string
          group_id: string
          name: string
          description: string | null
          price_cents: number
          is_available: boolean
          position: number
          max_quantity: number
          created_at: string
          updated_at: string
          deleted_at: string | null
        }
        Insert: {
          id?: string
          restaurant_id: string
          group_id: string
          name: string
          description?: string | null
          price_cents?: number
          is_available?: boolean
          position?: number
          max_quantity?: number
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
        }
        Update: {
          id?: string
          restaurant_id?: string
          group_id?: string
          name?: string
          description?: string | null
          price_cents?: number
          is_available?: boolean
          position?: number
          max_quantity?: number
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "addons_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "addon_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "addons_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          }
        ]
      }
      addresses: {
        Row: {
          id: string
          user_id: string
          label: string
          recipient: string | null
          street: string
          number: string
          complement: string | null
          district: string
          city: string
          state: string
          postal_code: string
          reference_point: string | null
          latitude: number | null
          longitude: number | null
          is_default: boolean
          created_at: string
          updated_at: string
          deleted_at: string | null
        }
        Insert: {
          id?: string
          user_id: string
          label?: string
          recipient?: string | null
          street: string
          number: string
          complement?: string | null
          district: string
          city: string
          state: string
          postal_code: string
          reference_point?: string | null
          latitude?: number | null
          longitude?: number | null
          is_default?: boolean
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
        }
        Update: {
          id?: string
          user_id?: string
          label?: string
          recipient?: string | null
          street?: string
          number?: string
          complement?: string | null
          district?: string
          city?: string
          state?: string
          postal_code?: string
          reference_point?: string | null
          latitude?: number | null
          longitude?: number | null
          is_default?: boolean
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "addresses_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          }
        ]
      }
      banners: {
        Row: {
          id: string
          title: string
          image_url: string
          target_url: string | null
          restaurant_id: string | null
          position: number
          starts_at: string
          ends_at: string | null
          is_active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          title: string
          image_url: string
          target_url?: string | null
          restaurant_id?: string | null
          position?: number
          starts_at?: string
          ends_at?: string | null
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          title?: string
          image_url?: string
          target_url?: string | null
          restaurant_id?: string | null
          position?: number
          starts_at?: string
          ends_at?: string | null
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "banners_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          }
        ]
      }
      cart_item_addons: {
        Row: {
          id: string
          cart_item_id: string
          addon_id: string
          quantity: number
        }
        Insert: {
          id?: string
          cart_item_id: string
          addon_id: string
          quantity?: number
        }
        Update: {
          id?: string
          cart_item_id?: string
          addon_id?: string
          quantity?: number
        }
        Relationships: [
          {
            foreignKeyName: "cart_item_addons_addon_id_fkey"
            columns: ["addon_id"]
            isOneToOne: false
            referencedRelation: "addons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cart_item_addons_cart_item_id_fkey"
            columns: ["cart_item_id"]
            isOneToOne: false
            referencedRelation: "cart_items"
            referencedColumns: ["id"]
          }
        ]
      }
      cart_items: {
        Row: {
          id: string
          cart_id: string
          product_id: string
          quantity: number
          notes: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          cart_id: string
          product_id: string
          quantity?: number
          notes?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          cart_id?: string
          product_id?: string
          quantity?: number
          notes?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "cart_items_cart_id_fkey"
            columns: ["cart_id"]
            isOneToOne: false
            referencedRelation: "carts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cart_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          }
        ]
      }
      carts: {
        Row: {
          id: string
          user_id: string
          restaurant_id: string
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          restaurant_id: string
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          restaurant_id?: string
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "carts_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "carts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          }
        ]
      }
      categories: {
        Row: {
          id: string
          restaurant_id: string
          name: string
          description: string | null
          position: number
          is_active: boolean
          created_at: string
          updated_at: string
          deleted_at: string | null
        }
        Insert: {
          id?: string
          restaurant_id: string
          name: string
          description?: string | null
          position?: number
          is_active?: boolean
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
        }
        Update: {
          id?: string
          restaurant_id?: string
          name?: string
          description?: string | null
          position?: number
          is_active?: boolean
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "categories_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          }
        ]
      }
      coupon_redemptions: {
        Row: {
          id: string
          coupon_id: string
          order_id: string
          user_id: string
          discount_cents: number
          created_at: string
        }
        Insert: {
          id?: string
          coupon_id: string
          order_id: string
          user_id: string
          discount_cents: number
          created_at?: string
        }
        Update: {
          id?: string
          coupon_id?: string
          order_id?: string
          user_id?: string
          discount_cents?: number
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "coupon_redemptions_coupon_id_fkey"
            columns: ["coupon_id"]
            isOneToOne: false
            referencedRelation: "coupons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "coupon_redemptions_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "coupon_redemptions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          }
        ]
      }
      coupons: {
        Row: {
          id: string
          scope: Database["public"]["Enums"]["coupon_scope"]
          restaurant_id: string | null
          code: string
          description: string | null
          discount: Database["public"]["Enums"]["discount_type"]
          value: number
          max_discount_cents: number | null
          min_order_cents: number
          starts_at: string
          ends_at: string | null
          max_uses: number | null
          max_uses_per_customer: number
          used_count: number
          first_order_only: boolean
          is_active: boolean
          created_at: string
          updated_at: string
          deleted_at: string | null
        }
        Insert: {
          id?: string
          scope?: Database["public"]["Enums"]["coupon_scope"]
          restaurant_id?: string | null
          code: string
          description?: string | null
          discount: Database["public"]["Enums"]["discount_type"]
          value?: number
          max_discount_cents?: number | null
          min_order_cents?: number
          starts_at?: string
          ends_at?: string | null
          max_uses?: number | null
          max_uses_per_customer?: number
          used_count?: number
          first_order_only?: boolean
          is_active?: boolean
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
        }
        Update: {
          id?: string
          scope?: Database["public"]["Enums"]["coupon_scope"]
          restaurant_id?: string | null
          code?: string
          description?: string | null
          discount?: Database["public"]["Enums"]["discount_type"]
          value?: number
          max_discount_cents?: number | null
          min_order_cents?: number
          starts_at?: string
          ends_at?: string | null
          max_uses?: number | null
          max_uses_per_customer?: number
          used_count?: number
          first_order_only?: boolean
          is_active?: boolean
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "coupons_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          }
        ]
      }
      couriers: {
        Row: {
          id: string
          user_id: string
          status: Database["public"]["Enums"]["courier_status"]
          availability: Database["public"]["Enums"]["courier_availability"]
          vehicle_type: string
          vehicle_plate: string | null
          document: string | null
          current_latitude: number | null
          current_longitude: number | null
          location_updated_at: string | null
          rating_avg: number
          rating_count: number
          deliveries_count: number
          approved_at: string | null
          approved_by: string | null
          created_at: string
          updated_at: string
          deleted_at: string | null
          restaurant_id: string | null
        }
        Insert: {
          id?: string
          user_id: string
          status?: Database["public"]["Enums"]["courier_status"]
          availability?: Database["public"]["Enums"]["courier_availability"]
          vehicle_type?: string
          vehicle_plate?: string | null
          document?: string | null
          current_latitude?: number | null
          current_longitude?: number | null
          location_updated_at?: string | null
          rating_avg?: number
          rating_count?: number
          deliveries_count?: number
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
          restaurant_id?: string | null
        }
        Update: {
          id?: string
          user_id?: string
          status?: Database["public"]["Enums"]["courier_status"]
          availability?: Database["public"]["Enums"]["courier_availability"]
          vehicle_type?: string
          vehicle_plate?: string | null
          document?: string | null
          current_latitude?: number | null
          current_longitude?: number | null
          location_updated_at?: string | null
          rating_avg?: number
          rating_count?: number
          deliveries_count?: number
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
          restaurant_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "couriers_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "couriers_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "couriers_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          }
        ]
      }
      deliveries: {
        Row: {
          id: string
          order_id: string
          restaurant_id: string
          courier_id: string | null
          status: Database["public"]["Enums"]["delivery_status"]
          courier_fee_cents: number
          distance_km: number | null
          assigned_at: string | null
          picked_up_at: string | null
          delivered_at: string | null
          cancelled_at: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          order_id: string
          restaurant_id: string
          courier_id?: string | null
          status?: Database["public"]["Enums"]["delivery_status"]
          courier_fee_cents?: number
          distance_km?: number | null
          assigned_at?: string | null
          picked_up_at?: string | null
          delivered_at?: string | null
          cancelled_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          order_id?: string
          restaurant_id?: string
          courier_id?: string | null
          status?: Database["public"]["Enums"]["delivery_status"]
          courier_fee_cents?: number
          distance_km?: number | null
          assigned_at?: string | null
          picked_up_at?: string | null
          delivered_at?: string | null
          cancelled_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "deliveries_courier_id_fkey"
            columns: ["courier_id"]
            isOneToOne: false
            referencedRelation: "couriers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deliveries_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: true
            referencedRelation: "orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deliveries_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          }
        ]
      }
      notifications: {
        Row: {
          id: string
          user_id: string
          title: string
          body: string
          kind: string
          order_id: string | null
          url: string | null
          read_at: string | null
          created_at: string
        }
        Insert: {
          id?: string
          user_id: string
          title: string
          body: string
          kind?: string
          order_id?: string | null
          url?: string | null
          read_at?: string | null
          created_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          title?: string
          body?: string
          kind?: string
          order_id?: string | null
          url?: string | null
          read_at?: string | null
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          }
        ]
      }
      order_item_addons: {
        Row: {
          id: string
          order_item_id: string
          addon_id: string | null
          addon_name: string
          group_name: string | null
          unit_price_cents: number
          quantity: number
          total_cents: number
        }
        Insert: {
          id?: string
          order_item_id: string
          addon_id?: string | null
          addon_name: string
          group_name?: string | null
          unit_price_cents?: number
          quantity?: number
          total_cents: number
        }
        Update: {
          id?: string
          order_item_id?: string
          addon_id?: string | null
          addon_name?: string
          group_name?: string | null
          unit_price_cents?: number
          quantity?: number
          total_cents?: number
        }
        Relationships: [
          {
            foreignKeyName: "order_item_addons_addon_id_fkey"
            columns: ["addon_id"]
            isOneToOne: false
            referencedRelation: "addons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_item_addons_order_item_id_fkey"
            columns: ["order_item_id"]
            isOneToOne: false
            referencedRelation: "order_items"
            referencedColumns: ["id"]
          }
        ]
      }
      order_items: {
        Row: {
          id: string
          order_id: string
          product_id: string | null
          product_name: string
          product_image_url: string | null
          unit_price_cents: number
          quantity: number
          addons_total_cents: number
          total_cents: number
          notes: string | null
          created_at: string
        }
        Insert: {
          id?: string
          order_id: string
          product_id?: string | null
          product_name: string
          product_image_url?: string | null
          unit_price_cents: number
          quantity: number
          addons_total_cents?: number
          total_cents: number
          notes?: string | null
          created_at?: string
        }
        Update: {
          id?: string
          order_id?: string
          product_id?: string | null
          product_name?: string
          product_image_url?: string | null
          unit_price_cents?: number
          quantity?: number
          addons_total_cents?: number
          total_cents?: number
          notes?: string | null
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "order_items_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          }
        ]
      }
      order_status_history: {
        Row: {
          id: string
          order_id: string
          from_status: Database["public"]["Enums"]["order_status"] | null
          to_status: Database["public"]["Enums"]["order_status"]
          changed_by: string | null
          note: string | null
          created_at: string
        }
        Insert: {
          id?: string
          order_id: string
          from_status?: Database["public"]["Enums"]["order_status"] | null
          to_status: Database["public"]["Enums"]["order_status"]
          changed_by?: string | null
          note?: string | null
          created_at?: string
        }
        Update: {
          id?: string
          order_id?: string
          from_status?: Database["public"]["Enums"]["order_status"] | null
          to_status?: Database["public"]["Enums"]["order_status"]
          changed_by?: string | null
          note?: string | null
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "order_status_history_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_status_history_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id"]
          }
        ]
      }
      orders: {
        Row: {
          id: string
          number: number
          restaurant_id: string
          customer_id: string | null
          customer_name: string
          customer_phone: string | null
          status: Database["public"]["Enums"]["order_status"]
          fulfillment: Database["public"]["Enums"]["fulfillment_type"]
          address_id: string | null
          address_summary: string | null
          address_district: string | null
          address_city: string | null
          address_postal_code: string | null
          address_latitude: number | null
          address_longitude: number | null
          subtotal_cents: number
          delivery_fee_cents: number
          discount_cents: number
          total_cents: number
          commission_cents: number
          coupon_id: string | null
          coupon_code: string | null
          notes: string | null
          scheduled_for: string | null
          confirmed_at: string | null
          ready_at: string | null
          delivered_at: string | null
          cancelled_at: string | null
          cancellation_reason: string | null
          created_at: string
          updated_at: string
          table_id: string | null
          table_label: string | null
        }
        Insert: {
          id?: string
          number: number
          restaurant_id: string
          customer_id?: string | null
          customer_name: string
          customer_phone?: string | null
          status?: Database["public"]["Enums"]["order_status"]
          fulfillment?: Database["public"]["Enums"]["fulfillment_type"]
          address_id?: string | null
          address_summary?: string | null
          address_district?: string | null
          address_city?: string | null
          address_postal_code?: string | null
          address_latitude?: number | null
          address_longitude?: number | null
          subtotal_cents?: number
          delivery_fee_cents?: number
          discount_cents?: number
          total_cents?: number
          commission_cents?: number
          coupon_id?: string | null
          coupon_code?: string | null
          notes?: string | null
          scheduled_for?: string | null
          confirmed_at?: string | null
          ready_at?: string | null
          delivered_at?: string | null
          cancelled_at?: string | null
          cancellation_reason?: string | null
          created_at?: string
          updated_at?: string
          table_id?: string | null
          table_label?: string | null
        }
        Update: {
          id?: string
          number?: number
          restaurant_id?: string
          customer_id?: string | null
          customer_name?: string
          customer_phone?: string | null
          status?: Database["public"]["Enums"]["order_status"]
          fulfillment?: Database["public"]["Enums"]["fulfillment_type"]
          address_id?: string | null
          address_summary?: string | null
          address_district?: string | null
          address_city?: string | null
          address_postal_code?: string | null
          address_latitude?: number | null
          address_longitude?: number | null
          subtotal_cents?: number
          delivery_fee_cents?: number
          discount_cents?: number
          total_cents?: number
          commission_cents?: number
          coupon_id?: string | null
          coupon_code?: string | null
          notes?: string | null
          scheduled_for?: string | null
          confirmed_at?: string | null
          ready_at?: string | null
          delivered_at?: string | null
          cancelled_at?: string | null
          cancellation_reason?: string | null
          created_at?: string
          updated_at?: string
          table_id?: string | null
          table_label?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "orders_address_id_fkey"
            columns: ["address_id"]
            isOneToOne: false
            referencedRelation: "addresses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_coupon_fkey"
            columns: ["coupon_id"]
            isOneToOne: false
            referencedRelation: "coupons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_table_id_fkey"
            columns: ["table_id"]
            isOneToOne: false
            referencedRelation: "restaurant_tables"
            referencedColumns: ["id"]
          }
        ]
      }
      payments: {
        Row: {
          id: string
          order_id: string
          method: Database["public"]["Enums"]["payment_method"]
          timing: Database["public"]["Enums"]["payment_timing"]
          status: Database["public"]["Enums"]["payment_status"]
          amount_cents: number
          change_for_cents: number | null
          provider: string | null
          provider_ref: string | null
          provider_payload: Json | null
          pix_qr_code: string | null
          pix_expires_at: string | null
          paid_at: string | null
          refunded_at: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          order_id: string
          method: Database["public"]["Enums"]["payment_method"]
          timing: Database["public"]["Enums"]["payment_timing"]
          status?: Database["public"]["Enums"]["payment_status"]
          amount_cents: number
          change_for_cents?: number | null
          provider?: string | null
          provider_ref?: string | null
          provider_payload?: Json | null
          pix_qr_code?: string | null
          pix_expires_at?: string | null
          paid_at?: string | null
          refunded_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          order_id?: string
          method?: Database["public"]["Enums"]["payment_method"]
          timing?: Database["public"]["Enums"]["payment_timing"]
          status?: Database["public"]["Enums"]["payment_status"]
          amount_cents?: number
          change_for_cents?: number | null
          provider?: string | null
          provider_ref?: string | null
          provider_payload?: Json | null
          pix_qr_code?: string | null
          pix_expires_at?: string | null
          paid_at?: string | null
          refunded_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payments_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id"]
          }
        ]
      }
      platform_categories: {
        Row: {
          id: string
          slug: string
          name: string
          icon: string | null
          image_url: string | null
          position: number
          is_active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          slug: string
          name: string
          icon?: string | null
          image_url?: string | null
          position?: number
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          slug?: string
          name?: string
          icon?: string | null
          image_url?: string | null
          position?: number
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      platform_settings: {
        Row: {
          id: boolean
          brand_name: string
          support_email: string | null
          support_phone: string | null
          default_commission_bps: number
          default_courier_fee_cents: number
          min_order_cents: number
          allow_new_signups: boolean
          maintenance_mode: boolean
          updated_at: string
        }
        Insert: {
          id?: boolean
          brand_name?: string
          support_email?: string | null
          support_phone?: string | null
          default_commission_bps?: number
          default_courier_fee_cents?: number
          min_order_cents?: number
          allow_new_signups?: boolean
          maintenance_mode?: boolean
          updated_at?: string
        }
        Update: {
          id?: boolean
          brand_name?: string
          support_email?: string | null
          support_phone?: string | null
          default_commission_bps?: number
          default_courier_fee_cents?: number
          min_order_cents?: number
          allow_new_signups?: boolean
          maintenance_mode?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      products: {
        Row: {
          id: string
          restaurant_id: string
          category_id: string
          name: string
          description: string | null
          image_url: string | null
          price_cents: number
          promo_price_cents: number | null
          promo_starts_at: string | null
          promo_ends_at: string | null
          is_available: boolean
          is_featured: boolean
          position: number
          serves_people: number | null
          prep_minutes: number | null
          track_stock: boolean
          stock_quantity: number
          sold_count: number
          created_at: string
          updated_at: string
          deleted_at: string | null
        }
        Insert: {
          id?: string
          restaurant_id: string
          category_id: string
          name: string
          description?: string | null
          image_url?: string | null
          price_cents: number
          promo_price_cents?: number | null
          promo_starts_at?: string | null
          promo_ends_at?: string | null
          is_available?: boolean
          is_featured?: boolean
          position?: number
          serves_people?: number | null
          prep_minutes?: number | null
          track_stock?: boolean
          stock_quantity?: number
          sold_count?: number
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
        }
        Update: {
          id?: string
          restaurant_id?: string
          category_id?: string
          name?: string
          description?: string | null
          image_url?: string | null
          price_cents?: number
          promo_price_cents?: number | null
          promo_starts_at?: string | null
          promo_ends_at?: string | null
          is_available?: boolean
          is_featured?: boolean
          position?: number
          serves_people?: number | null
          prep_minutes?: number | null
          track_stock?: boolean
          stock_quantity?: number
          sold_count?: number
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "products_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "products_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          }
        ]
      }
      profiles: {
        Row: {
          id: string
          full_name: string
          email: string | null
          phone: string | null
          avatar_url: string | null
          platform_role: Database["public"]["Enums"]["platform_role"]
          is_active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id: string
          full_name?: string
          email?: string | null
          phone?: string | null
          avatar_url?: string | null
          platform_role?: Database["public"]["Enums"]["platform_role"]
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          full_name?: string
          email?: string | null
          phone?: string | null
          avatar_url?: string | null
          platform_role?: Database["public"]["Enums"]["platform_role"]
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "profiles_id_fkey"
            columns: ["id"]
            isOneToOne: true
            referencedRelation: "users"
            referencedColumns: ["id"]
          }
        ]
      }
      push_subscriptions: {
        Row: {
          id: string
          user_id: string
          endpoint: string
          p256dh: string
          auth: string
          descricao: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          endpoint: string
          p256dh: string
          auth: string
          descricao?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          endpoint?: string
          p256dh?: string
          auth?: string
          descricao?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "push_subscriptions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          }
        ]
      }
      restaurant_hours: {
        Row: {
          id: string
          restaurant_id: string
          weekday: number
          opens_at: string
          closes_at: string
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          restaurant_id: string
          weekday: number
          opens_at: string
          closes_at: string
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          restaurant_id?: string
          weekday?: number
          opens_at?: string
          closes_at?: string
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "restaurant_hours_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          }
        ]
      }
      restaurant_members: {
        Row: {
          id: string
          restaurant_id: string
          user_id: string
          role: Database["public"]["Enums"]["restaurant_role"]
          is_active: boolean
          created_at: string
          updated_at: string
          deleted_at: string | null
        }
        Insert: {
          id?: string
          restaurant_id: string
          user_id: string
          role?: Database["public"]["Enums"]["restaurant_role"]
          is_active?: boolean
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
        }
        Update: {
          id?: string
          restaurant_id?: string
          user_id?: string
          role?: Database["public"]["Enums"]["restaurant_role"]
          is_active?: boolean
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "restaurant_members_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "restaurant_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          }
        ]
      }
      restaurant_order_counters: {
        Row: {
          restaurant_id: string
          last_number: number
        }
        Insert: {
          restaurant_id: string
          last_number?: number
        }
        Update: {
          restaurant_id?: string
          last_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "restaurant_order_counters_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: true
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          }
        ]
      }
      restaurant_payment_methods: {
        Row: {
          restaurant_id: string
          method: Database["public"]["Enums"]["payment_method"]
          timing: Database["public"]["Enums"]["payment_timing"]
          is_active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          restaurant_id: string
          method: Database["public"]["Enums"]["payment_method"]
          timing: Database["public"]["Enums"]["payment_timing"]
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          restaurant_id?: string
          method?: Database["public"]["Enums"]["payment_method"]
          timing?: Database["public"]["Enums"]["payment_timing"]
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "restaurant_payment_methods_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          }
        ]
      }
      restaurant_platform_categories: {
        Row: {
          restaurant_id: string
          category_id: string
        }
        Insert: {
          restaurant_id: string
          category_id: string
        }
        Update: {
          restaurant_id?: string
          category_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "restaurant_platform_categories_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "platform_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "restaurant_platform_categories_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          }
        ]
      }
      restaurant_tables: {
        Row: {
          id: string
          restaurant_id: string
          label: string
          code: string
          seats: number | null
          is_active: boolean
          created_at: string
          updated_at: string
          deleted_at: string | null
        }
        Insert: {
          id?: string
          restaurant_id: string
          label: string
          code: string
          seats?: number | null
          is_active?: boolean
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
        }
        Update: {
          id?: string
          restaurant_id?: string
          label?: string
          code?: string
          seats?: number | null
          is_active?: boolean
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "restaurant_tables_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          }
        ]
      }
      restaurants: {
        Row: {
          id: string
          slug: string
          name: string
          legal_name: string | null
          document: string | null
          description: string | null
          logo_url: string | null
          cover_url: string | null
          phone: string | null
          email: string | null
          status: Database["public"]["Enums"]["restaurant_status"]
          is_open: boolean
          accepts_scheduled_orders: boolean
          street: string | null
          number: string | null
          complement: string | null
          district: string | null
          city: string | null
          state: string | null
          postal_code: string | null
          latitude: number | null
          longitude: number | null
          delivery_fee_cents: number
          free_delivery_above_cents: number | null
          min_order_cents: number
          delivery_radius_km: number
          avg_prep_minutes: number
          avg_delivery_minutes: number
          commission_bps: number
          rating_avg: number
          rating_count: number
          approved_at: string | null
          approved_by: string | null
          created_at: string
          updated_at: string
          deleted_at: string | null
          accepts_platform_couriers: boolean
          timezone: string
          aberto_agora: boolean | null
          no_horario: boolean | null
        }
        Insert: {
          id?: string
          slug: string
          name: string
          legal_name?: string | null
          document?: string | null
          description?: string | null
          logo_url?: string | null
          cover_url?: string | null
          phone?: string | null
          email?: string | null
          status?: Database["public"]["Enums"]["restaurant_status"]
          is_open?: boolean
          accepts_scheduled_orders?: boolean
          street?: string | null
          number?: string | null
          complement?: string | null
          district?: string | null
          city?: string | null
          state?: string | null
          postal_code?: string | null
          latitude?: number | null
          longitude?: number | null
          delivery_fee_cents?: number
          free_delivery_above_cents?: number | null
          min_order_cents?: number
          delivery_radius_km?: number
          avg_prep_minutes?: number
          avg_delivery_minutes?: number
          commission_bps?: number
          rating_avg?: number
          rating_count?: number
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
          accepts_platform_couriers?: boolean
          timezone?: string
        }
        Update: {
          id?: string
          slug?: string
          name?: string
          legal_name?: string | null
          document?: string | null
          description?: string | null
          logo_url?: string | null
          cover_url?: string | null
          phone?: string | null
          email?: string | null
          status?: Database["public"]["Enums"]["restaurant_status"]
          is_open?: boolean
          accepts_scheduled_orders?: boolean
          street?: string | null
          number?: string | null
          complement?: string | null
          district?: string | null
          city?: string | null
          state?: string | null
          postal_code?: string | null
          latitude?: number | null
          longitude?: number | null
          delivery_fee_cents?: number
          free_delivery_above_cents?: number | null
          min_order_cents?: number
          delivery_radius_km?: number
          avg_prep_minutes?: number
          avg_delivery_minutes?: number
          commission_bps?: number
          rating_avg?: number
          rating_count?: number
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          updated_at?: string
          deleted_at?: string | null
          accepts_platform_couriers?: boolean
          timezone?: string
        }
        Relationships: [
          {
            foreignKeyName: "restaurants_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          }
        ]
      }
      reviews: {
        Row: {
          id: string
          order_id: string
          restaurant_id: string
          customer_id: string
          courier_id: string | null
          restaurant_rating: number
          courier_rating: number | null
          comment: string | null
          reply: string | null
          replied_at: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          order_id: string
          restaurant_id: string
          customer_id: string
          courier_id?: string | null
          restaurant_rating: number
          courier_rating?: number | null
          comment?: string | null
          reply?: string | null
          replied_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          order_id?: string
          restaurant_id?: string
          customer_id?: string
          courier_id?: string | null
          restaurant_rating?: number
          courier_rating?: number | null
          comment?: string | null
          reply?: string | null
          replied_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "reviews_courier_id_fkey"
            columns: ["courier_id"]
            isOneToOne: false
            referencedRelation: "couriers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reviews_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reviews_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: true
            referencedRelation: "orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reviews_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          }
        ]
      }
      stock_movements: {
        Row: {
          id: string
          restaurant_id: string
          product_id: string
          kind: Database["public"]["Enums"]["stock_movement_type"]
          quantity: number
          balance_after: number
          order_id: string | null
          reason: string | null
          created_by: string | null
          created_at: string
        }
        Insert: {
          id?: string
          restaurant_id: string
          product_id: string
          kind: Database["public"]["Enums"]["stock_movement_type"]
          quantity: number
          balance_after: number
          order_id?: string | null
          reason?: string | null
          created_by?: string | null
          created_at?: string
        }
        Update: {
          id?: string
          restaurant_id?: string
          product_id?: string
          kind?: Database["public"]["Enums"]["stock_movement_type"]
          quantity?: number
          balance_after?: number
          order_id?: string | null
          reason?: string | null
          created_by?: string | null
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "stock_movements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_movements_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_movements_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_movements_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "restaurants"
            referencedColumns: ["id"]
          }
        ]
      }
    }
    Views: Record<string, never>
    Functions: {
      cadastrar_estabelecimento: {
        Args: {
          p_nome: string
          p_telefone: string
          p_rua: string
          p_numero: string
          p_bairro: string
          p_cidade: string
          p_estado?: string
          p_cep?: string
          p_complemento?: string
          p_documento?: string
          p_descricao?: string
          p_email?: string
        }
        Returns: { id: string; slug: string }[]
      }
      criar_mesas: {
        Args: {
          p_restaurante: string
          p_quantidade: number
          p_prefixo?: string
        }
        Returns: number
      }
      fechar_pedido: {
        Args: {
          p_cart_id: string
          p_fulfillment: Database["public"]["Enums"]["fulfillment_type"]
          p_payment_method: Database["public"]["Enums"]["payment_method"]
          p_payment_timing: Database["public"]["Enums"]["payment_timing"]
          p_address_id?: string
          p_change_for_cents?: number
          p_coupon_code?: string
          p_notes?: string
          p_scheduled_for?: string
          p_mesa?: string
        }
        Returns: string
      }
      onde_esta_o_entregador: {
        Args: {
          p_order: string
        }
        Returns: Json
      }
      publicar_posicao: {
        Args: {
          p_latitude: number
          p_longitude: number
        }
        Returns: undefined
      }
      simular_cupom: {
        Args: {
          p_code: string
          p_restaurant: string
          p_subtotal_cents: number
          p_delivery_fee_cents: number
        }
        Returns: Json
      }
    }
    Enums: {
      coupon_scope: "platform" | "restaurant"
      courier_availability: "offline" | "online" | "on_delivery"
      courier_status: "pending" | "approved" | "suspended"
      delivery_status: "pending" | "searching_courier" | "assigned" | "heading_to_restaurant" | "picked_up" | "heading_to_customer" | "delivered" | "cancelled"
      discount_type: "percentage" | "fixed" | "free_shipping"
      fulfillment_type: "delivery" | "pickup" | "dine_in"
      order_status: "awaiting_payment" | "received" | "confirmed" | "preparing" | "ready" | "out_for_delivery" | "delivered" | "cancelled" | "rejected"
      payment_method: "pix" | "credit_card" | "debit_card" | "cash" | "meal_voucher"
      payment_status: "pending" | "paid" | "failed" | "refunded" | "cancelled"
      payment_timing: "online" | "on_delivery"
      platform_role: "customer" | "courier" | "platform_admin"
      restaurant_role: "owner" | "manager" | "staff"
      restaurant_status: "pending" | "approved" | "suspended" | "rejected"
      stock_movement_type: "in" | "out" | "adjustment"
    }
    CompositeTypes: Record<string, never>
  }
}

/** Apelido curto, usado pelos clientes em src/lib/supabase. */
export type Banco = Database

type Publico = Database["public"]

export type Tabelas<T extends keyof Publico["Tables"]> = Publico["Tables"][T]["Row"]
export type NovoEm<T extends keyof Publico["Tables"]> = Publico["Tables"][T]["Insert"]
export type AlteracaoEm<T extends keyof Publico["Tables"]> = Publico["Tables"][T]["Update"]
export type Enums<T extends keyof Publico["Enums"]> = Publico["Enums"][T]
