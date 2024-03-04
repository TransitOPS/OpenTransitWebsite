defmodule Dotcom.Application do
  @moduledoc """
  Starts all processes needed to support the Phoenix application for MBTA.com.
  This includes a variety of caches, Supervisors starting assorted GenServers,
  and finally the Phoenix Endpoint. These are listed in a particular order, as
  some processes depend on other processes having started.
  """

  use Application

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    Application.put_env(
      :dotcom,
      :allow_indexing,
      DotcomWeb.ControllerHelpers.environment_allows_indexing?()
    )

    # hack to pull the STATIC_SCHEME variable out of the environment
    Application.put_env(
      :dotcom,
      DotcomWeb.Endpoint,
      update_static_url(Application.get_env(:dotcom, DotcomWeb.Endpoint))
    )

    children =
      [
        # Start the endpoint when the application starts
        %{
          id: ConCache,
          start:
            {ConCache, :start_link,
             [
               [
                 ttl: :timer.seconds(60),
                 ttl_check: :timer.seconds(5),
                 ets_options: [read_concurrency: true]
               ],
               [name: :line_diagram_realtime_cache]
             ]}
        },
        RepoCache.Log,
        {Application.get_env(:dotcom, :cms_cache, CMS.Cache), []},
        Dotcom.Cache.TripPlanFeedback.Cache,
        CMS.Telemetry,
        V3Api.Cache,
        Schedules.Repo,
        Schedules.RepoCondensed,
        Facilities.Repo,
        Stops.Repo
      ] ++
        if Application.get_env(:dotcom, :start_data_processes) do
          [
            Vehicles.Supervisor,
            Supervisor.child_spec(
              {Dotcom.Stream.Vehicles,
               name: :vehicle_marker_channel_broadcaster, topic: "vehicles"},
              id: :vehicle_marker_channel_broadcaster
            ),
            Supervisor.child_spec(
              {Dotcom.Stream.Vehicles, name: :vehicles_channel_broadcaster, topic: "vehicles-v2"},
              id: :vehicles_channel_broadcaster
            ),
            {Dotcom.GreenLine.Supervisor, name: Dotcom.GreenLine.Supervisor}
          ]
        else
          []
        end ++
        [
          {Dotcom.React, name: Dotcom.React},
          Routes.Supervisor,
          Algolia.Api,
          LocationService,
          Services.Repo,
          RoutePatterns.Repo,
          Predictions.Supervisor,
          Dotcom.RealtimeSchedule,
          {Phoenix.PubSub, name: Dotcom.PubSub},
          Alerts.Supervisor,
          Fares.Supervisor,
          {DotcomWeb.Endpoint, name: DotcomWeb.Endpoint}
        ]

    opts = [strategy: :one_for_one, name: Dotcom.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    DotcomWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp update_static_url([{:static_url, static_url_parts} | rest]) do
    static_url_parts = Keyword.update(static_url_parts, :scheme, nil, &update_static_url_scheme/1)
    [{:static_url, static_url_parts} | update_static_url(rest)]
  end

  defp update_static_url([first | rest]) do
    [first | update_static_url(rest)]
  end

  defp update_static_url([]) do
    []
  end

  defp update_static_url_scheme({:system, env_var}), do: System.get_env(env_var)
  defp update_static_url_scheme(scheme), do: scheme
end
