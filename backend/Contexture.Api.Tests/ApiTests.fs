module Contexture.Api.Tests.ApiTests

open System
open System.IO
open System.Net.Http
open Contexture.Api.Aggregates
open Contexture.Api.Aggregates.BoundedContext
open Contexture.Api.Aggregates.Domain
open Contexture.Api.Aggregates.Namespace
open Contexture.Api.Entities
open Contexture.Api.Infrastructure
open Microsoft.AspNetCore.Hosting
open Microsoft.Extensions.Hosting
open Microsoft.Extensions.Http
open Microsoft.Extensions.DependencyInjection
open Microsoft.AspNetCore.TestHost
open Microsoft.Extensions.Logging
open Xunit
open FSharp.Control.Tasks
open Xunit.Sdk

module TestHost =
    let configureLogging (builder: ILoggingBuilder) =
        builder.AddConsole().AddDebug() |> ignore

    let createHost configureServices configure =
        Host
            .CreateDefaultBuilder()
            .UseContentRoot(Directory.GetCurrentDirectory())
            .UseEnvironment("Tests")
            .ConfigureServices(Action<_, _> configureServices)
            .ConfigureWebHostDefaults(fun (webHost: IWebHostBuilder) ->
                webHost
                    .Configure(Action<_> configure)
                    .UseTestServer()
                    .ConfigureLogging(configureLogging)
                |> ignore)
            .ConfigureLogging(configureLogging)
            .Build()

    let runServer () =
        let host =
            createHost Contexture.Api.App.configureServices Contexture.Api.App.configureApp

        host.Start()
        host

    let staticClock time = fun () -> time

module Utils =
    open System.Net.Http.Json

    let asEvent id event =
        fun clock ->
            { Event = event
              Metadata = { Source = id; RecordedAt = clock () } }

    let append clock (eventStore: EventStore) =
        fun events ->
            events
            |> List.map (fun e -> e clock)
            |> eventStore.Append

    let postJson (client: HttpClient) (url: string) (jsonContent: string) =
        task {
            let! result = client.PostAsync(url, new StringContent(jsonContent))
            return result.EnsureSuccessStatusCode()
        }

    let getJson<'t> (client: HttpClient) (url: string) =
        task {
            let! result = client.GetFromJsonAsync<'t>(url)
            return result
        }

    let singleEvent<'e> (eventStore: EventStore) : EventEnvelope<'e> =
        let events = eventStore.Get<'e>()
        Assert.Single events

module Fixtures =
    let newDomain domainId =
        DomainCreated { DomainId = domainId; Name = "" }
        |> Utils.asEvent domainId

    let newBoundedContext domainId contextId =
        BoundedContextCreated
            { BoundedContextId = contextId
              Name = ""
              DomainId = domainId }
        |> Utils.asEvent contextId


    let newLabel () =
        { LabelId = Guid.NewGuid()
          Name = "label"
          Value = Some "value"
          Template = None }

module Namespaces =

    [<Fact>]
    let ``Can create a new namespace`` () =
        task {
            use server = TestHost.runServer ()

            let clock = TestHost.staticClock DateTime.UtcNow

            let eventStore =
                server.Services.GetRequiredService<EventStore>()

            // arrange
            let domainId = Guid.NewGuid()
            let contextId = Guid.NewGuid()

            Utils.append clock eventStore [ Fixtures.newDomain domainId ]
            Utils.append clock eventStore [ Fixtures.newBoundedContext domainId contextId ]

            //act
            use client = server.GetTestClient()

            let createNamespaceContent = "{
                    \"name\":  \"test\",
                    \"labels\": [
                        { \"name\": \"l1\", \"value\": \"v1\" },
                        { \"name\": \"l2\", \"value\": \"v2\" }
                    ]
                }"

            let! _ =
                Utils.postJson client (sprintf "api/boundedContexts/%O/namespaces" contextId) createNamespaceContent

            // assert
            let event =
                Utils.singleEvent<Namespace.Event> eventStore

            match event.Event with
            | NamespaceAdded n ->
                Assert.Equal("test", n.Name)

                Assert.Collection(
                    n.Labels,
                    (fun (l: LabelDefinition) ->
                        Assert.Equal("l1", l.Name)
                        Assert.Equal(l.Value, Some "v1")),
                    (fun (l: LabelDefinition) ->
                        Assert.Equal("l2", l.Name)
                        Assert.Equal(l.Value, Some "v2"))
                )
            | e -> raise (XunitException $"Unexpected event: %O{e}")
        }

    [<Fact>]
    let ``Can list bounded contexts by label and value`` () =
        task {
            use server = TestHost.runServer ()

            let clock = TestHost.staticClock DateTime.UtcNow

            let eventStore =
                server.Services.GetRequiredService<EventStore>()

            // arrange
            let namespaceId = Guid.NewGuid()
            let contextId = Guid.NewGuid()

            let added =
                NamespaceAdded
                    { BoundedContextId = contextId
                      Name = "namespace"
                      NamespaceId = namespaceId
                      NamespaceTemplateId = None
                      Labels =
                          [ { Fixtures.newLabel () with
                                  Name = "l1"
                                  Value = Some "v1" }
                            { Fixtures.newLabel () with
                                  Name = "l2"
                                  Value = Some "v2" } ] }
                |> Utils.asEvent contextId

            Utils.append clock eventStore [ added ]

            //act
            use client = server.GetTestClient()

            let! result =
                Utils.getJson<BoundedContextId array>
                    client
                    (sprintf "api/namespaces/boundedContextsWithLabel/%s/%s" "l1" "v1")

            // assert
            Assert.NotEmpty result
            Assert.Contains(contextId, result)
        }

    [<Fact>]
    let ``Can search for bounded contexts by label and value`` () =
        task {
            use server = TestHost.runServer ()

            let clock = TestHost.staticClock DateTime.UtcNow

            let eventStore =
                server.Services.GetRequiredService<EventStore>()

            // arrange
            let namespaceId = Guid.NewGuid()
            let contextId = Guid.NewGuid()

            let added =
                NamespaceAdded
                    { BoundedContextId = contextId
                      Name = "namespace"
                      NamespaceId = namespaceId
                      NamespaceTemplateId = None
                      Labels = [ Fixtures.newLabel () ] }
                |> Utils.asEvent contextId

            Utils.append clock eventStore [ added ]

            //act - search by name
            use client = server.GetTestClient()

            let! result =
                Utils.getJson<BoundedContextId array>
                    client
                    (sprintf "api/namespaces/boundedContextsWithLabel?name=%s" "lab")

            // assert
            Assert.NotEmpty result
            Assert.Collection(result, (fun x -> Assert.Equal(contextId, x)))

            //act - search by value
            use client = server.GetTestClient()

            let! result =
                Utils.getJson<BoundedContextId array>
                    client
                    (sprintf "api/namespaces/boundedContextsWithLabel?value=%s" "val")

            // assert
            Assert.NotEmpty result
            Assert.Collection(result, (fun x -> Assert.Equal(contextId, x)))
        }

    [<Fact>]
    let ``Can search for bounded contexts by label and value for a specific template`` () =
        task {
            use server = TestHost.runServer ()

            let clock = TestHost.staticClock DateTime.UtcNow

            let eventStore =
                server.Services.GetRequiredService<EventStore>()

            // arrange
            let namespaceId = Guid.NewGuid()
            let contextId = Guid.NewGuid()
            let otherContextId = Guid.NewGuid()
            let templateId = Guid.NewGuid()

            let added =
                NamespaceAdded
                    { BoundedContextId = contextId
                      Name = "namespace"
                      NamespaceId = namespaceId
                      NamespaceTemplateId = Some templateId
                      Labels = [ Fixtures.newLabel () ] }
                |> Utils.asEvent contextId

            let addedOther =
                NamespaceAdded
                    { BoundedContextId = otherContextId
                      Name = "the other namespace"
                      NamespaceId = Guid.NewGuid()
                      NamespaceTemplateId = None
                      Labels = [ Fixtures.newLabel () ] }
                |> Utils.asEvent otherContextId

            Utils.append clock eventStore [ added; addedOther ]

            //act - search by name
            use client = server.GetTestClient()

            let! result =
                Utils.getJson<BoundedContextId array>
                    client
                    (sprintf "api/namespaces/boundedContextsWithLabel?name=%s&NamespaceTemplate=%O" "lab" templateId)

            // assert
            Assert.NotEmpty result
            Assert.Collection(result, (fun x -> Assert.Equal(contextId, x)))

            //act - search by value
            use client = server.GetTestClient()

            let! result =
                Utils.getJson<BoundedContextId array>
                    client
                    (sprintf "api/namespaces/boundedContextsWithLabel?value=%s&NamespaceTemplate=%O" "val" templateId)

            // assert
            Assert.NotEmpty result
            Assert.Collection(result, (fun x -> Assert.Equal(contextId, x)))
        }