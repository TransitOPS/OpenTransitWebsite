defmodule SiteWeb.CustomerSupportControllerTest do
  use SiteWeb.ConnCase

  import Phoenix.HTML, only: [safe_to_string: 1, html_escape: 1]
  import SiteWeb.CustomerSupportController

  setup do
    conn =
      default_conn()
      |> put_req_header("x-forwarded-for", "10.108.98.#{Enum.random(0..999)}")

    {:ok, conn: conn}
  end

  describe "GET" do
    test "shows the support form", %{conn: conn} do
      conn = get(conn, customer_support_path(conn, :index))
      response = html_response(conn, 200)
      assert response =~ "Customer Support"
    end

    test "shows the support form and accepts a comment param", %{conn: conn} do
      conn =
        get(conn, customer_support_path(conn, :index, %{comments: "A comment about the MBTA"}))

      response = html_response(conn, 200)
      assert response =~ "Customer Support"
      assert response =~ "A comment about the MBTA"
    end

    test "sets the service options on the connection", %{conn: conn} do
      conn = get(conn, customer_support_path(conn, :index))

      assert conn.assigns.service_options == Feedback.Message.service_options()
    end

    test "sets a custom meta description", %{conn: conn} do
      conn = get(conn, customer_support_path(conn, :index))

      assert conn.assigns.meta_description
    end
  end

  describe "POST" do
    def valid_request_response_data do
      %{
        "support" => %{
          "comments" => "comments",
          "email" => "test@gmail.com",
          "privacy" => "on",
          "phone" => "",
          "first_name" => "tom",
          "last_name" => "brady",
          "no_request_response" => "off",
          "service" => "Inquiry",
          "subject" => "Website",
          "date_time" => %{
            "year" => 2020,
            "month" => 10,
            "day" => 20,
            "hour" => 10,
            "minute" => 15,
            "am_pm" => "AM"
          }
        },
        "g-recaptcha-response" => "valid_response"
      }
    end

    def valid_no_response_data do
      %{
        "support" => %{
          "comments" => "comments",
          "no_request_response" => "on",
          "service" => "Inquiry",
          "date_time" => %{
            "year" => 2020,
            "month" => 10,
            "day" => 20,
            "hour" => 10,
            "minute" => 15,
            "am_pm" => "AM"
          }
        },
        "g-recaptcha-response" => "valid_response"
      }
    end

    test "shows a thank you message on success and sends an email", %{conn: conn} do
      conn = post(conn, customer_support_path(conn, :submit), valid_request_response_data())

      response = html_response(conn, 302)
      refute response =~ "form id=\"support-form\""
      assert redirected_to(conn) == customer_support_path(conn, :thanks)
      wait_for_ticket_task(conn)

      assert String.contains?(
               Feedback.Test.latest_message()["text"],
               ~s(<MBTASOURCE>Auto Ticket 2</MBTASOURCE>)
             )
    end

    test "submits successfully if customer does not want a response", %{conn: conn} do
      conn = post(conn, customer_support_path(conn, :submit), valid_no_response_data())

      refute conn.assigns["errors"]
      wait_for_ticket_task(conn)
    end

    test "sets a custom meta description", %{conn: conn} do
      conn = post(conn, customer_support_path(conn, :submit), valid_request_response_data())

      assert conn.assigns.meta_description
    end

    test "validates presence of comments", %{conn: conn} do
      conn =
        post(
          conn,
          customer_support_path(conn, :submit),
          put_in(valid_request_response_data(), ["support", "comments"], "")
        )

      assert "comments" in conn.assigns.errors
    end

    test "validates the presence of the service type", %{conn: conn} do
      conn =
        post(
          conn,
          customer_support_path(conn, :submit),
          put_in(valid_request_response_data(), ["support", "service"], "")
        )

      assert "service" in conn.assigns.errors
    end

    test "validates that the service is one of the allowed values", %{conn: conn} do
      conn =
        post(
          conn,
          customer_support_path(conn, :submit),
          put_in(valid_request_response_data(), ["support", "service"], "Hug")
        )

      assert "service" in conn.assigns.errors
    end

    test "validates that the subject is one of the allowed values for the service", %{conn: conn} do
      conn =
        post(
          conn,
          customer_support_path(conn, :submit),
          put_in(valid_request_response_data(), ["support", "subject"], "Bad")
        )

      assert "subject" in conn.assigns.errors
    end

    test "requires first_name if customer does want a response", %{conn: conn} do
      conn =
        post(
          conn,
          customer_support_path(conn, :submit),
          put_in(valid_request_response_data(), ["support", "first_name"], "")
        )

      assert "first_name" in conn.assigns.errors
    end

    test "requires last_name if customer does want a response", %{conn: conn} do
      conn =
        post(
          conn,
          customer_support_path(conn, :submit),
          put_in(valid_request_response_data(), ["support", "last_name"], "")
        )

      assert "last_name" in conn.assigns.errors
    end

    test "invalid with no email when the customer wants a response", %{conn: conn} do
      conn =
        post(
          conn,
          customer_support_path(conn, :submit),
          put_in(valid_request_response_data(), ["support", "email"], "")
        )

      assert "email" in conn.assigns.errors
    end

    test "requires a real email", %{conn: conn} do
      conn =
        post(
          conn,
          customer_support_path(conn, :submit),
          put_in(valid_request_response_data(), ["support", "email"], "not an email")
        )

      assert "email" in conn.assigns.errors
    end

    test "invalid with phone but no email when the customer wants a response", %{conn: conn} do
      conn =
        post(
          conn,
          customer_support_path(conn, :submit),
          valid_request_response_data()
          |> put_in(["support", "email"], "")
          |> put_in(["support", "phone"], "555-555-5555")
        )

      assert "email" in conn.assigns.errors
    end

    test "requires privacy checkbox when customer wants a response", %{conn: conn} do
      conn =
        post(
          conn,
          customer_support_path(conn, :submit),
          put_in(valid_request_response_data(), ["support", "privacy"], "")
        )

      assert "privacy" in conn.assigns.errors
    end

    test "attaches photos in params", %{conn: conn} do
      File.write!("/tmp/upload-1", "upload 1 data")
      File.write!("/tmp/upload-2", "upload 2 data")

      params =
        valid_no_response_data()
        |> put_in(["support", "photos"], [
          %Plug.Upload{filename: "photo-1.jpg", path: "/tmp/upload-1"},
          %Plug.Upload{filename: "photo-2.jpg", path: "/tmp/upload-2"}
        ])

      conn = post(conn, customer_support_path(conn, :submit), params)

      wait_for_ticket_task(conn)
      attachments = Feedback.Test.latest_message()["attachments"]

      assert attachments == [
               %{"filename" => "photo-1.jpg", "data" => "upload 1 data"},
               %{"filename" => "photo-2.jpg", "data" => "upload 2 data"}
             ]
    end

    test "prevents submissions when an upload does not appear to be an image", %{conn: conn} do
      params =
        valid_request_response_data()
        |> put_in(["support", "photos"], [
          %Plug.Upload{filename: "image.jpg"},
          %Plug.Upload{filename: "runme.exe"}
        ])

      conn =
        post(
          conn,
          customer_support_path(conn, :submit),
          params
        )

      assert "photos" in conn.assigns.errors
    end

    test "logs a warning, returns 429, and shows an error when rate limit reached", %{conn: conn} do
      path = customer_support_path(conn, :submit)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          conn =
            Enum.reduce(1..4, conn, fn _, acc ->
              acc
              |> recycle()
              |> post(path, valid_request_response_data())
            end)

          assert conn.status == 429
          assert conn.assigns.errors == ["rate limit"]
        end)

      assert log =~ "rate limit exceeded"
    end

    test "requires a successful recaptcha response", %{conn: conn} do
      conn =
        post(
          conn,
          customer_support_path(conn, :submit),
          put_in(valid_no_response_data(), ["g-recaptcha-response"], "invalid_response")
        )

      assert "recaptcha" in conn.assigns.errors
    end

    test "adds date and time fields if not present in the form", %{conn: conn} do
      conn =
        post(
          conn,
          customer_support_path(conn, :submit),
          %{
            "support" => %{
              "comments" => "comments",
              "email" => "test@gmail.com",
              "privacy" => "on",
              "phone" => "",
              "first_name" => "tom",
              "last_name" => "brady",
              "no_request_response" => "off",
              "service" => "Inquiry",
              "subject" => "Website"
            },
            "g-recaptcha-response" => "valid_response"
          }
        )

      assert redirected_to(conn) == customer_support_path(conn, :thanks)
    end
  end

  describe "Expandable blocks" do
    test "renders an expandable block", %{conn: conn} do
      block = [
        %{
          header: %{text: "Call Us", iconSvgText: nil},
          id: "call_us",
          initially_expanded: true
        }
      ]

      conn = assign(conn, :view_module, SiteWeb.CustomerSupportView)

      rendered =
        safe_to_string(
          html_escape(
            SiteWeb.CustomerSupportController.render_expandable_blocks(conn.assigns, block)
          )
        )

      anchor = Floki.find(rendered, ".c-expandable-block__link")
      assert Enum.count(anchor) == 1
    end

    test "fails gracefully if template does not exist", %{conn: conn} do
      block = [
        %{
          header: %{text: "Does not exist", iconSvgText: nil},
          id: "nonexistent",
          initially_expanded: true
        }
      ]

      conn = assign(conn, :view_module, SiteWeb.CustomerSupportView)

      rendered =
        safe_to_string(
          html_escape(
            SiteWeb.CustomerSupportController.render_expandable_blocks(conn.assigns, block)
          )
        )

      assert rendered == ""
    end

    test "sets date to today if it's in the future", %{conn: conn} do
      current_year = DateTime.utc_now().year
      m = DateTime.utc_now().month
      d = DateTime.utc_now().day

      current_day =
        if d < 10 do
          "0#{d}"
        else
          d
        end

      current_month =
        if m < 10 do
          "0#{m}"
        else
          m
        end

      two_months_from_now = Util.now() |> Timex.shift(months: 2)

      conn =
        post(
          conn |> assign(:all_options_per_mode, %{}),
          customer_support_path(conn, :submit),
          put_in(valid_request_response_data(), ["support", "date_time"], two_months_from_now)
        )

      wait_for_ticket_task(conn)
      message = Feedback.Test.latest_message()["text"]

      regex = ~r"\<INCIDENTDATE\>(.+?)\<\/INCIDENTDATE\>"
      [_, date_from_message] = Regex.run(regex, message)

      assert String.contains?(
               date_from_message,
               "#{current_month}/#{current_day}/#{current_year}"
             )
    end

    test "submits the date as is because it's not in the future", %{conn: conn} do
      current_year = DateTime.utc_now().year
      m = DateTime.utc_now().month
      d = DateTime.utc_now().day

      current_day =
        if d < 10 do
          "0#{d}"
        else
          d
        end

      current_month =
        if m < 10 do
          "0#{m}"
        else
          m
        end

      conn =
        post(
          conn,
          customer_support_path(conn, :submit),
          put_in(valid_request_response_data(), ["support", "date_time"], Util.now())
        )

      wait_for_ticket_task(conn)
      message = Feedback.Test.latest_message()["text"]

      regex = ~r"\<INCIDENTDATE\>(.+?)\<\/INCIDENTDATE\>"
      [_, date_from_message] = Regex.run(regex, message)

      assert String.contains?(
               date_from_message,
               "#{current_month}/#{current_day}/#{current_year}"
             )
    end
  end

  describe "Date and time selector" do
    test "renders a date and time selector", %{conn: conn} do
      conn = get(conn, customer_support_path(conn, :index))
      rendered = html_response(conn, 200)

      # check there are date and time selectors:
      refute Floki.find(rendered, "div[id=\"support-time-select\"]") == []
      refute Floki.find(rendered, "select[id=\"support_date_time_hour\"]") == []
      refute Floki.find(rendered, "select[id=\"support_date_time_minute\"]") == []
      refute Floki.find(rendered, "select[id=\"support_date_time_am_pm\"]") == []

      refute Floki.find(rendered, "div[id=\"support-date\"]") == []
    end
  end

  describe "Mode, route and vehicle" do
    test "get_all_modes" do
      assert SiteWeb.CustomerSupportView.get_all_modes() == [
               [key: "Select", value: " "],
               [key: "Subway", value: "Subway"],
               [key: "Commuter Rail", value: "Commuter Rail"],
               [key: "Bus", value: "Bus Other"],
               [key: "Ferry", value: "Ferry"],
               [key: "The RIDE", value: "The RIDE"]
             ]
    end

    test "get_options_per_mode" do
      options_per_mode = get_options_per_mode()

      assert Map.has_key?(options_per_mode, "bus_options")
      assert Map.has_key?(options_per_mode, "commuter_rail_options")
      assert Map.has_key?(options_per_mode, "subway_options")
      assert Map.has_key?(options_per_mode, "ferry_options")
    end

    test "get_routes_for_mode", %{conn: conn} do
      conn = get(conn, customer_support_path(conn, :index))

      assert get_routes_for_mode(conn, :subway) == [
               "Red Line",
               "Blue Line",
               "Orange Line",
               "Green Line"
             ]

      refute get_routes_for_mode(conn, :bus) == []
      refute get_routes_for_mode(conn, :commuter_rail) == []
      refute get_routes_for_mode(conn, :ferry) == []
    end
  end

  defp wait_for_ticket_task(%{private: %{ticket_task: pid}}) do
    # since the ticket sending is running in the background, we want to wait
    # for it to finish so that we're only running one test e-mail at a time.
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, _, _, _}, 1_000
    :ok
  end
end
