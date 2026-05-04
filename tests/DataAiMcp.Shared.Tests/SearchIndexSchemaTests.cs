using DataAiMcp.Shared.Search;
using FluentAssertions;
using Xunit;

namespace DataAiMcp.Shared.Tests;

public sealed class SearchIndexSchemaTests
{
    [Fact]
    public void Build_includesAllExpectedFields()
    {
        var index = SearchIndexSchema.Build();
        index.Name.Should().Be(SearchIndexSchema.IndexName);
        index.Fields.Should().Contain(f => f.Name == SearchIndexSchema.IdField && f.IsKey == true);
        index.Fields.Should().Contain(f => f.Name == SearchIndexSchema.ContentVectorField);
        index.VectorSearch!.Profiles.Should().HaveCount(1);
        index.SemanticSearch!.Configurations.Should().HaveCount(1);
    }
}
