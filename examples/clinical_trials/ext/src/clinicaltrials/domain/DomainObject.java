package clinicaltrials.domain;

public class DomainObject
{
    private Long id;

    public DomainObject()
    {
    }

    /**
     * @return the database identifier
     */
    public Long getId()
    {
        return id;
    }

    /**
     * @param id the id to set
     */
    public void setId(Long id)
    {
        this.id = id;
    }
}
